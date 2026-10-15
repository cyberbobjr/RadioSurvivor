"""Tests hors jeu du générateur des nœuds d'animation Living Knox (LK02-T05, LK04-T11) : tools/gen_animsets.py.

    python RadioSurvivor/tests/test_gen_animsets.py

Vérifie : table valide, XML bien formés et complets (sans x_extends), noms et chemins (minuscules, AnimSets/zombie
avec la casse vanilla), aucune collision avec un nœud vanilla, condition d'acteur exclusive partout, choix d'un seul
de nos nœuds par combinaison de variables (algorithme de AnimState.getAnimNodes et AnimNode.compareSelectionConditions,
Java 42.21.0, reproduit ici), nœuds d'escalade (événements SetVariable présents, aucun OnFloor, choisis pour un acteur
et l'issue success seulement), --check vert sur les fichiers commités et rouge sur un fichier modifié, absent ou en trop.
Les contrôles qui lisent le jeu installé (clips, dossiers vanilla) sont SKIP si le dossier vanilla est absent.
"""
from __future__ import annotations

import copy
import itertools
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_animsets as gen  # noqa: E402

VANILLA = gen.DEFAULT_VANILLA
HAS_VANILLA = (VANILLA / 'AnimSets' / 'zombie').is_dir()


# ------------------------------------------------------------------ selection model (Java 42.21.0)

class Node:
    def __init__(self, name, priority, conds, abstract=False):
        self.name, self.priority, self.conds, self.abstract = name, priority, conds, abstract


def compare(a: Node, b: Node) -> int:
    """AnimNode.compareSelectionConditions (AnimNode.java:287-310)."""
    if a.abstract != b.abstract:
        return -1 if a.abstract else 1
    if a.priority != b.priority:
        return -1 if a.priority < b.priority else 1
    if len(a.conds) != len(b.conds):
        return -1 if len(a.conds) < len(b.conds) else 1
    return 0


def add_node(nodes: list, new: Node) -> None:
    """AnimState.addNode (AnimState.java:78-91): inserted before the first node it beats."""
    if new.abstract:
        return
    for i, node in enumerate(nodes):
        if compare(new, node) > 0:
            nodes.insert(i, new)
            return
    nodes.append(new)


def check(cond, variables: dict) -> bool:
    """AnimCondition.check (STRING, BOOL; a missing variable: STRING equals "", BOOL equals false)."""
    name, ctype, value = cond
    present = name.lower() in variables
    actual = variables.get(name.lower())
    if ctype == 'BOOL':
        expected = value == 'true'
        return (not expected) if not present else (actual is True) == expected
    if ctype == 'STRING':
        return value.lower() == ('' if not present else str(actual).lower())
    raise AssertionError(f'condition type {ctype} not modelled')


def select(nodes: list, variables: dict) -> list:
    """AnimState.getAnimNodes (AnimState.java:44-52): best passing node plus following nodes of the same rank."""
    out, best = [], None
    for node in nodes:
        if best is not None and compare(best, node) > 0:
            break
        if not all(check(c, variables) for c in node.conds):
            continue
        best = node
        out.append(node)
    return out


def our_nodes(table: dict, state: str) -> list:
    return [Node(n['name'], table['conditionPriority'], gen.conditions(table, n, state))
            for n in table['nodes'] if state in n['states']]


def stand_in_vanilla(state: str) -> list:
    """Vanilla nodes as seen by the selection: priority 0 with 0 to 3 conditions (always passing here), and in
    pathfind the ragdoll vehicle collision node (priority 10, conditions useRagdollVehicleCollison and canRagdoll)."""
    nodes = [Node(f'vanilla{i}', 0, [('dummy', 'BOOL', 'false')] * i) for i in range(4)]
    if state == 'pathfind':
        nodes.append(Node('ragdollVehicleCollision', 10, [('useRagdollVehicleCollison', 'BOOL', 'true'),
                                                           ('canRagdoll', 'BOOL', 'true')]))
    return nodes


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.table = gen.load_table()
        self.files = gen.expected_files(self.table)

    def test_committed_files_are_up_to_date(self):
        self.assertEqual(gen.compare(self.table), [])
        proc = subprocess.run([sys.executable, str(ROOT / 'tools' / 'gen_animsets.py'), '--check'],
                              capture_output=True, text=True, encoding='utf-8', errors='replace')
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn('OK: ', proc.stdout)

    def test_well_formed_complete_files(self):
        self.assertEqual(len(self.files), sum(len(n['states']) for n in self.table['nodes']))
        for path, text in self.files.items():
            self.assertTrue(text.isascii(), path)
            root = ET.fromstring(text)
            self.assertEqual(root.tag, 'animNode', path)
            self.assertEqual(root.attrib, {}, f'{path}: attribute (x_extends?) on the root')
            self.assertNotIn('x_extends', text)
            for tag in ('m_Name', 'm_AnimName', 'm_ConditionPriority', 'm_Looped', 'm_BlendTime', 'm_SpeedScale'):
                self.assertIsNotNone(root.find(tag), f'{path}: {tag}')
            self.assertEqual(int(root.find('m_ConditionPriority').text), self.table['conditionPriority'])
            conds = root.findall('m_Conditions')
            first = [conds[0].find(t).text for t in ('m_Name', 'm_Type', 'm_Value')]
            self.assertEqual(first, [self.table['actorVariable'], 'BOOL', 'true'], path)
            self.assertNotIn('OR', [c.find('m_Type').text for c in conds], path)
            float(root.find('m_SpeedScale').text)

    def test_lower_case_names_and_exact_paths(self):
        for path in self.files:
            rel = path.relative_to(gen.MOD).as_posix()
            self.assertRegex(rel, r'^common/media/AnimSets/zombie/[a-z-]+/lkactor_[a-z0-9_]+\.xml$')
            self.assertEqual(path.name, path.name.lower())
        on_disk = [p.relative_to(gen.MOD).as_posix() for p in gen.existing_files()]
        self.assertEqual(sorted(on_disk), sorted(p.relative_to(gen.MOD).as_posix() for p in self.files))
        # Casse réelle des dossiers sur le disque (Windows ne la contrôle pas : comparer les noms listés).
        media = gen.MOD / 'common' / 'media'
        self.assertIn('AnimSets', [p.name for p in media.iterdir()])
        self.assertIn('zombie', [p.name for p in (media / 'AnimSets').iterdir()])
        self.assertEqual(sorted(p.name for p in gen.OUT.iterdir()), sorted(self.table['states']))

    @unittest.skipUnless(HAS_VANILLA, f'vanilla media folder not found: {VANILLA}')
    def test_vanilla_states_clips_and_no_collision(self):
        self.assertEqual(gen.check_vanilla(self.table, VANILLA), [])
        zombie = VANILLA / 'AnimSets' / 'zombie'
        vanilla_states = {p.name for p in zombie.iterdir() if p.is_dir()}
        for state in self.table['states']:
            self.assertIn(state, vanilla_states)  # même casse que le dossier vanilla
            vanilla_files = {p.name.lower() for p in (zombie / state).iterdir()}
            for node in self.table['nodes']:
                if state in node['states']:
                    self.assertNotIn(node['file'].lower(), vanilla_files)
        broken = copy.deepcopy(self.table)
        broken['nodes'][0]['clip'] = 'Bob_DoesNotExist'
        self.assertTrue(any('Bob_DoesNotExist' in p for p in gen.check_vanilla(broken, VANILLA)))
        broken = copy.deepcopy(self.table)
        broken['nodes'][0]['file'] = 'defaultidle.xml'
        self.assertTrue(any('collides' in p for p in gen.check_vanilla(broken, VANILLA)))

    def test_actor_condition_is_exclusive_and_one_node_per_combination(self):
        gestures = self.table['gestures'] + ['dance']
        weapons = [None, '', 'firearm', 'handgun', '1handed', '2handed', 'knife']
        for state in self.table['states']:
            nodes = []
            for n in stand_in_vanilla(state) + our_nodes(self.table, state):
                add_node(nodes, n)
            ours = {n.name for n in our_nodes(self.table, state)}
            for actor, gesture, weapon, moving, ragdoll in itertools.product(
                    [None, False, True], [None] + gestures, weapons, [None, True, False], [False, True]):
                variables = {}
                for name, value in ((self.table['actorVariable'], actor), (self.table['gestureVariable'], gesture),
                                    ('Weapon', weapon), ('bMoving', moving)):
                    if value is not None:
                        variables[name.lower()] = value
                if ragdoll:
                    variables.update({'useragdollvehiclecollison': True, 'canragdoll': True})
                picked = [n.name for n in select(nodes, variables)]
                where = f'{state} {variables}'
                if actor is not True:
                    self.assertFalse(set(picked) & ours, f'{where}: our node picked for an ordinary zombie')
                elif ragdoll and state == 'pathfind':
                    self.assertEqual(picked, ['ragdollVehicleCollision'], where)
                else:
                    self.assertEqual(len(picked), 1, f'{where}: {picked}')
                    self.assertIn(picked[0], ours, where)

    def test_expected_node_per_gesture(self):
        def pick(state, **v):
            nodes = []
            for n in stand_in_vanilla(state) + our_nodes(self.table, state):
                add_node(nodes, n)
            variables = {self.table['actorVariable'].lower(): True}
            variables.update({k.lower(): val for k, val in v.items()})
            return [n.name for n in select(nodes, variables)]
        g = self.table['gestureVariable']
        idle = {'idle': 'LKActorIdle', 'walk': 'LKActorIdle', 'run': 'LKActorIdle', 'crouch': 'LKActorCrouchIdle',
                'aim': 'LKActorAimHandgun', 'guard': 'LKActorGuard2H', 'strike': 'LKActorStrike2H',
                'sit': 'LKActorSit'}
        for gesture, node in idle.items():
            self.assertEqual(pick('idle', **{g: gesture}), [node], gesture)
        self.assertEqual(pick('idle', **{g: 'aim', 'Weapon': 'firearm'}), ['LKActorAimRifle'])
        self.assertEqual(pick('idle', **{g: 'aim', 'Weapon': 'handgun'}), ['LKActorAimHandgun'])
        self.assertEqual(pick('idle', **{g: 'guard', 'Weapon': '1handed'}), ['LKActorGuard1H'])
        self.assertEqual(pick('idle', **{g: 'strike', 'Weapon': '1handed'}), ['LKActorStrike1H'])
        # Tir (LK06-T03) : arme de poing ou sans arme, arme longue (Weapon = firearm).
        self.assertEqual(pick('idle', **{g: 'shoot', 'Weapon': 'handgun'}), ['LKActorShootHandgun'])
        self.assertEqual(pick('idle', **{g: 'shoot', 'Weapon': 'firearm'}), ['LKActorShootRifle'])
        self.assertEqual(pick('idle', **{g: 'reload', 'Weapon': 'handgun'}), ['LKActorReloadHandgun'])
        self.assertEqual(pick('idle', **{g: 'reload', 'Weapon': 'firearm'}), ['LKActorReloadRifle'])
        self.assertEqual(pick('idle'), ['LKActorIdle'])  # variable de geste absente
        for state in ('walktoward', 'walktoward-network'):
            self.assertEqual(pick(state, **{g: 'walk'}), ['LKActorWalk'])
            self.assertEqual(pick(state, **{g: 'aim'}), ['LKActorWalk'])
            self.assertEqual(pick(state, **{g: 'run'}), ['LKActorRun'])
            self.assertEqual(pick(state, **{g: 'crouch'}), ['LKActorCrouchWalk'])
        self.assertEqual(pick('pathfind', **{g: 'run', 'bMoving': True}), ['LKActorRun'])
        self.assertEqual(pick('pathfind', **{g: 'run', 'bMoving': False}), ['LKActorPathWaitIdle'])
        self.assertEqual(pick('pathfind', **{g: 'crouch', 'bMoving': False}), ['LKActorPathWaitCrouch'])
        self.assertEqual(pick('pathfind', **{g: 'walk', 'bMoving': True}), ['LKActorWalk'])

    def test_climb_nodes_events(self):
        """LK04-T11 : nœuds d'escalade sans OnFloor, avec les SetVariable qui font avancer l'état Java."""
        progress = self.table['progress']
        climb = [(p, t) for p, t in self.files.items() if p.parent.name in progress]
        self.assertEqual(len(climb), 4)
        for path, text in climb:
            started, finished = progress[path.parent.name]
            root = ET.fromstring(text)
            self.assertEqual(root.find('m_Looped').text, 'false', path)
            events = [(e.find('m_EventName').text, e.find('m_ParameterValue').text) for e in root.findall('m_Events')]
            self.assertNotIn('OnFloor', text, path)
            self.assertTrue({n for n, _ in events} <= gen.EVENT_NAMES, path)
            for e in root.findall('m_Events'):  # un seul repère de temps, valide
                times = [c.tag for c in e if c.tag in ('m_Time', 'm_TimePc')]
                self.assertEqual(len(times), 1, path)
                if times[0] == 'm_Time':
                    self.assertIn(e.find('m_Time').text, ('Start', 'End'), path)
                else:
                    self.assertTrue(0.0 <= float(e.find('m_TimePc').text) <= 1.0, path)
            conds = {(c.find('m_Name').text, c.find('m_Value').text) for c in root.findall('m_Conditions')}
            if (started, 'false') in conds:
                self.assertIn(('SetVariable', f'{started}=true'), events, path)
            else:
                self.assertIn((started, 'true'), conds, path)
                self.assertIn(('SetVariable', f'{finished}=true'), events, path)
                outcome = started.replace('Started', 'Outcome')
                self.assertIn((outcome, 'success'), conds, path)

    def test_climb_nodes_chosen_only_for_actor_and_success(self):
        """Choix dans climbwindow et climbfence avec les nœuds vanilla réels (conditions recopiées de 42.21.0) :
        notre départ pour un acteur avant ClimbXStarted, notre arrivée pour l'issue success seulement, jamais pour un
        zombie ordinaire ; les issues fall, falling, obstacle et lunge restent aux nœuds vanilla."""
        def vanilla(prefix, fall_outcome):
            s, o = f'Climb{prefix}Started', f'Climb{prefix}Outcome'
            return [Node('start', 0, [(s, 'BOOL', 'false')]),
                    Node('end', 0, [(s, 'BOOL', 'true'), (o, 'STRING', 'success')]),
                    Node('fall', 0, [(s, 'BOOL', 'true'), (o, 'STRING', fall_outcome), ('canRagdoll', 'BOOL', 'false')]),
                    Node('fall_RAG', 0, [(s, 'BOOL', 'true'), (o, 'STRING', fall_outcome), ('canRagdoll', 'BOOL', 'true'),
                                         ('canRagdoll', 'BOOL', 'true')]),
                    Node('obstacle', 0, [(s, 'BOOL', 'true'), (o, 'STRING', 'obstacle')]),
                    Node('lunge', 0, [(o, 'STRING', 'lunge'), (s, 'BOOL', 'true')])]
        cases = {'climbwindow': ('Window', 'fall', 'LKActorClimbWindowStart', 'LKActorClimbWindowEnd'),
                 'climbfence': ('Fence', 'falling', 'LKActorClimbFenceStart', 'LKActorClimbFenceEnd')}
        outcomes = [None, 'success', 'fall', 'falling', 'obstacle', 'lunge', 'rope']
        for state, (prefix, fall_outcome, start, end) in cases.items():
            nodes = []
            for n in vanilla(prefix, fall_outcome) + our_nodes(self.table, state):
                add_node(nodes, n)
            ours = {start, end}
            for actor, started, outcome, finished, ragdoll in itertools.product(
                    [None, False, True], [None, False, True], outcomes, [None, False, True], [False, True]):
                variables = {'canragdoll': ragdoll}
                for name, value in ((self.table['actorVariable'], actor), (f'Climb{prefix}Started', started),
                                    (f'Climb{prefix}Outcome', outcome), (f'Climb{prefix}Finished', finished)):
                    if value is not None:
                        variables[name.lower()] = value
                picked = [n.name for n in select(nodes, variables)]
                where = f'{state} {variables}'
                if actor is not True:
                    self.assertFalse(set(picked) & ours, f'{where}: our node picked for an ordinary zombie')
                elif started is not True:
                    self.assertEqual(picked, [start], where)
                elif outcome == 'success' and (state == 'climbwindow' or finished is not True):
                    self.assertEqual(picked, [end], where)
                else:
                    self.assertFalse(set(picked) & ours, f'{where}: our node picked for another outcome')

    def test_state_folders_cover_local_and_network_walks(self):
        for node in self.table['nodes']:
            if 'walktoward' in node['states']:
                self.assertIn('walktoward-network', node['states'], node['file'])  # copie distante en MP
                self.assertIn('pathfind', node['states'], node['file'])

    def test_invalid_tables_refused(self):
        def bad(change):
            t = copy.deepcopy(self.table)
            change(t)
            with self.assertRaises((gen.TableError, ValueError, KeyError)):
                gen.validate(t)
        bad(lambda t: t['nodes'][0].update(file='LKActor_Idle.xml'))
        bad(lambda t: t['nodes'][0].update(file='idle.xml'))
        bad(lambda t: t['nodes'][0].update(clip='Zombie_Idle'))
        bad(lambda t: t['nodes'][1].update(conditions=[['LKGesture', 'STRING', 'dance']]))
        bad(lambda t: t['nodes'][1].update(conditions=[['x', 'OR', '']]))
        bad(lambda t: t['nodes'][1].update(conditions=[['LKActor', 'BOOL', 'false']]))
        bad(lambda t: t['nodes'][0].update(states=['Idle']))
        bad(lambda t: t['nodes'].append(copy.deepcopy(t['nodes'][0])))
        bad(lambda t: t.update(conditionPriority=0))

        def climb(name):
            return next(i for i, n in enumerate(self.table['nodes']) if n['name'] == name)
        ws, we = climb('LKActorClimbWindowStart'), climb('LKActorClimbWindowEnd')
        fe = climb('LKActorClimbFenceEnd')
        bad(lambda t: t['nodes'][we]['events'].append(['OnFloor', '0.1', 'true']))
        bad(lambda t: t['nodes'][we]['events'].append(['SetState', '0.1', 'Attack']))
        bad(lambda t: t['nodes'][we].update(events=[e for e in t['nodes'][we]['events'] if 'Finished' not in e[2]]))
        bad(lambda t: t['nodes'][ws].update(events=[e for e in t['nodes'][ws]['events'] if 'Started' not in e[2]]))
        bad(lambda t: t['nodes'][fe].update(events=[e for e in t['nodes'][fe]['events'] if 'Finished' not in e[2]]))
        bad(lambda t: t['nodes'][ws].update(looped=True))
        bad(lambda t: t['nodes'][ws].update(conditions=[]))
        bad(lambda t: t['nodes'][we]['events'].append(['SetVariable', '1.5', 'X=true']))
        bad(lambda t: t['nodes'][we]['events'].append(['SetVariable', 'Middle', 'X=true']))
        bad(lambda t: t['nodes'][we]['events'].append(['SetVariable', '0.5', 'NoEquals']))
        bad(lambda t: t['nodes'][we]['events'].append(['PlaySound', '0.5', 'a<b']))

    # LK04-T13 : gestes d'ouverture et de fermeture d'une fenêtre ---------------------------------------------------
    WINDOW_NODES = {  # geste -> (premier nœud, second nœud, nœuds vanilla du joueur, son du second clip)
        'openwindow': ('LKActorOpenWindowStart', 'LKActorOpenWindow', ('openwindow/start.xml', 'openwindow/success.xml'),
                       'OpenWindow'),
        'closewindow': ('LKActorCloseWindowStart', 'LKActorCloseWindow',
                        ('closewindow/start.xml', 'closewindow/success.xml'), 'CloseWindow')}

    def node(self, name):
        return next(n for n in self.table['nodes'] if n['name'] == name)

    def test_window_gestures_two_clips_by_phase_and_only_when_standing(self):
        g, phase = self.table['gestureVariable'], self.table['phaseVariable']

        def pick(state, **v):
            nodes = []
            for n in stand_in_vanilla(state) + our_nodes(self.table, state):
                add_node(nodes, n)
            variables = {self.table['actorVariable'].lower(): True}
            variables.update({k.lower(): val for k, val in v.items()})
            return [n.name for n in select(nodes, variables)]
        for gesture, (first, second, _, _) in self.WINDOW_NODES.items():
            self.assertEqual(pick('idle', **{g: gesture}), [first], gesture)              # phase absente = faux
            self.assertEqual(pick('idle', **{g: gesture, phase: False}), [first], gesture)
            self.assertEqual(pick('idle', **{g: gesture, phase: True}), [second], gesture)
            self.assertEqual(pick('idle', **{g: gesture, phase: True, 'Weapon': 'firearm'}), [second], gesture)
            self.assertEqual(pick('pathfind', **{g: gesture, 'bMoving': False}), [first], gesture)
            self.assertEqual(pick('pathfind', **{g: gesture, phase: True}), [second], gesture)
            self.assertEqual(pick('pathfind', **{g: gesture, 'bMoving': True}), ['LKActorWalk'], gesture)
            for state in ('walktoward', 'walktoward-network'):
                self.assertEqual(pick(state, **{g: gesture}), ['LKActorWalk'], gesture)   # en marche : marche
            # Un zombie ordinaire ne passe jamais ces nœuds, quelle que soit la phase.
            for state in ('idle', 'pathfind'):
                nodes = []
                for n in stand_in_vanilla(state) + our_nodes(self.table, state):
                    add_node(nodes, n)
                for p in (None, False, True):
                    variables = {g.lower(): gesture}
                    if p is not None:
                        variables[phase.lower()] = p
                    picked = {n.name for n in select(nodes, variables)}
                    self.assertFalse(picked & {first, second}, (state, variables))

    def test_window_gesture_nodes_copy_the_player_nodes(self):
        phase = self.table['phaseVariable']
        for gesture, (first, second, proofs, sound) in self.WINDOW_NODES.items():
            self.assertIn(gesture, self.table['gestures'])
            for name, proof in zip((first, second), proofs):
                node = self.node(name)
                self.assertEqual(node['proof'], 'AnimSets/player/' + proof)
                self.assertFalse(node['looped'], name)
                self.assertEqual(sorted(node['states']), ['idle', 'pathfind'], name)
                self.assertEqual(node['stateConditions'], {'pathfind': [['bMoving', 'BOOL', 'false']]}, name)
                self.assertNotIn('OnFloor', json.dumps(node))
                if HAS_VANILLA:  # même clip et même vitesse que le nœud du joueur
                    root = ET.fromstring((VANILLA / node['proof']).read_text(encoding='utf-8'))
                    self.assertEqual(root.find('m_AnimName').text, node['clip'], name)
                    self.assertEqual(float(root.find('m_SpeedScale').text), float(node['speedScale']), name)
            self.assertIn(['SetVariable', 'End', f'{phase}=true'], self.node(first)['events'])
            self.assertIn(['PlaySound', 'Start', sound], self.node(second)['events'])
            self.assertNotIn('SetVariable', [e[0] for e in self.node(second)['events']])

    def test_phase_and_window_gestures_match_lk_anim(self):
        code = (gen.MOD / '42.21' / 'media' / 'lua' / 'shared' / 'LivingKnox' / 'LK_Anim.lua').read_text(encoding='utf-8')
        self.assertIn(f'Anim.VAR_PHASE = "{self.table["phaseVariable"]}"', code)
        acts = set(re.findall(r'(\w+) = true', re.search(r'Anim\.ACTS = \{([^}]*)\}', code).group(1)))
        self.assertLessEqual({'openwindow', 'closewindow'}, acts)
        # LK04-T04 : un geste ponctuel sans nœuds propres ("force", "wait") est joué par le clip d'un geste de la
        # table (Anim.ACT_CLIP).
        clips = dict(re.findall(r'(\w+) = "(\w+)"', re.search(r'Anim\.ACT_CLIP = \{([^}]*)\}', code).group(1)))
        for act in sorted(acts - {'openwindow', 'closewindow'}):
            self.assertIn(clips.get(act), self.table['gestures'], act)
        t = copy.deepcopy(self.table)
        t['phaseVariable'] = t['gestureVariable']
        with self.assertRaises(gen.TableError):
            gen.validate(t)
        t['phaseVariable'] = 'bad name'
        with self.assertRaises(gen.TableError):
            gen.validate(t)


class CheckModeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='lk-animsets-'))
        self.out = self.tmp / 'AnimSets' / 'zombie'
        self.table = gen.load_table()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_write_is_idempotent_and_check_detects_drift(self):
        self.assertTrue(gen.compare(self.table, self.out))  # rien d'écrit : tout manque
        written, removed = gen.write(self.table, self.out)
        self.assertEqual((written, removed), (len(gen.expected_files(self.table)), 0))
        self.assertEqual(gen.write(self.table, self.out), (0, 0))
        self.assertEqual(gen.compare(self.table, self.out), [])
        target = self.out / 'idle' / 'lkactor_aim.xml'
        target.write_text(target.read_text(encoding='utf-8').replace('aim', 'run'), encoding='utf-8')
        (self.out / 'pathfind' / 'lkactor_walk.xml').unlink()
        (self.out / 'idle' / 'lkactor_old.xml').write_text('<animNode/>', encoding='utf-8')
        (self.out / 'idle' / 'notours.xml').write_text('<animNode/>', encoding='utf-8')
        problems = gen.compare(self.table, self.out)
        self.assertEqual(sorted(problems), sorted(['stale or edited idle/lkactor_aim.xml',
                                                   'missing pathfind/lkactor_walk.xml',
                                                   'not in the table idle/lkactor_old.xml']))
        self.assertEqual(gen.write(self.table, self.out), (2, 1))
        self.assertEqual(gen.compare(self.table, self.out), [])
        self.assertTrue((self.out / 'idle' / 'notours.xml').is_file())  # fichier étranger jamais touché

    def test_crlf_checkout_still_up_to_date(self):
        gen.write(self.table, self.out)
        target = self.out / 'idle' / 'lkactor_idle.xml'
        target.write_bytes(target.read_bytes().replace(b'\n', b'\r\n'))
        self.assertEqual(gen.compare(self.table, self.out), [])


if __name__ == '__main__':
    unittest.main()
