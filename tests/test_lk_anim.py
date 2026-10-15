"""Tests hors jeu des gestes des corps de PNJ Living Knox (LK02-T05) : LK_Anim.lua.

    python RadioSurvivor/tests/test_lk_anim.py

Banc tests/harness.py et doublures de tests/test_lk_bodies.py et tests/test_lk_guard.py, complétées ici. Les
doublures reproduisent le Java 42.21.0 relevé ; elles NE PROUVENT PAS l'API réelle, seulement la logique :
- variables d'animation propres à chaque objet, noms insensibles à la casse (AnimationVariableHandle) ;
  setVariable(String, boolean | String) ; sur le serveur, setVariable d'un IsoZombie est sans effet
  (IsoGameCharacter.java:11374-11396) ; getVariableString d'une variable absente = "" et getVariableBoolean = false
  (IAnimationVariableSource.java:17-30) ; clearVariable (IsoGameCharacter.java:11427) ;
- non synchronisées : une copie cliente recréée (nouvel objet) n'a aucune variable.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list, LUA, DEV_LUA, ROOT  # noqa: E402
from test_lk_guard import GuardBase  # noqa: E402

ANIM = 'shared/LivingKnox/LK_Anim.lua'
RELAY = 'server/LivingKnox/LK_Relay.lua'
MOD_FILES = [LUA / ANIM, LUA / RELAY]
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKAnims.lua',
             DEV_LUA / 'client' / 'RST' / 'RST_LKBodiesClient.lua',
             DEV_LUA / 'server' / 'RST' / 'RST_LKBodiesServer.lua']

ANIM_DOUBLES = r'''
local H = HARNESS
local Z = H.classes.IsoZombie
VARSETS = 0
local function vars(self)
    local v = rawget(self, 'animVars')
    if not v then v = {}; self.animVars = v end
    return v
end
function Z:setVariable(key, value)
    if type(key) ~= 'string' then error('No implementation found for setVariable', 2) end
    local t = type(value)
    if t ~= 'string' and t ~= 'boolean' and t ~= 'number' then error('No implementation found for setVariable', 2) end
    if isServer() then return nil end  -- IsoGameCharacter.java:11385 : GameServer.server et IsoZombie
    VARSETS = VARSETS + 1
    vars(self)[string.lower(key)] = value
    return true
end
function Z:clearVariable(key) vars(self)[string.lower(key)] = nil end
function Z:getVariableString(key)
    local v = vars(self)[string.lower(key)]
    if v == nil then return '' end
    return tostring(v)
end
function Z:getVariableBoolean(key)
    local v = vars(self)[string.lower(key)]
    return v == true or v == 'true'
end
function ANIMVARS(zb)
    if zb == nil then return 'nil' end
    local v = rawget(zb, 'animVars') or {}
    return 'actor=' .. tostring(v.lkactor) .. ' gesture=' .. tostring(v.lkgesture)
end
'''


class AnimBase(GuardBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, ANIM_DOUBLES)
            h.load(m, ANIM)
        if self.mode == 'mp':
            # Relais des gestes (LK03-T05) : serveur seulement ; B dans le rayon d'envoi du PNJ (102, 102).
            h.load('server', RELAY)
            h.move_player('B', 96, 108, 0)
        return h

    def relay_tick(self):
        """Une image du serveur : publication et envoi du relais (LK03-T05)."""
        self.h.tick(1)

    def relayed(self):
        """Fenêtre de regroupement écoulée puis réseau livré : tout geste ou pose en attente est chez les clients."""
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()

    def vars(self, m, zid):
        return self.h.eval(m, f'ANIMVARS(HARNESS.zombies[{zid}])')

    def anim(self, code, m=None):
        return self.ev('LivingKnox.Anim.' + code, m)

    def apply(self, n=1):
        self.h.tick(n * self.ev('LivingKnox.Anim.APPLY_EVERY'))


class MultiplayerAnimTests(AnimBase):
    def mirror(self, zid, machines=('A', 'B')):
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "server")')

    def ready(self):
        zid = self.npc()
        self.mirror(zid)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def states(self):
        return [m for m in self.h.pending() if m['command'] == 'animState']

    def test_gesture_published_by_the_server_and_set_by_each_client_only(self):
        zid = self.ready()
        self.h.spawn_zombie(2000, 103, 102, 0)  # zombie vanilla voisin
        self.slow()
        for c in ('A', 'B'):
            self.assertEqual(self.vars(c, zid), 'actor=true gesture=idle')
        ok = self.anim('setGesture("lk-1", "aim")')
        self.assertIs(ok, True)
        self.assertEqual(self.states(), [])   # relais : envoi à l'image suivante du serveur
        self.relay_tick()
        msgs = self.states()
        self.assertEqual(sorted(m['to'] for m in msgs), ['A', 'B'])
        entry = dict(msgs[0]['args']['d']['lk-1'])   # copie : pending() partage les arguments en file
        self.assertIsInstance(entry.pop('r'), (int, float))
        self.assertEqual(entry, {'g': 'aim'})
        self.h.pump()
        self.apply()
        for c in ('A', 'B'):
            self.assertEqual(self.vars(c, zid), 'actor=true gesture=aim')
            self.assertEqual(self.vars(c, 2000), 'actor=nil gesture=nil')
        # Serveur : setVariable sans effet sur un zombie, et rien n'y est tenté.
        self.assertEqual(self.h.eval('server', 'VARSETS'), 0)
        self.assertEqual(self.vars('server', zid), 'actor=nil gesture=nil')
        # Même geste : rien de renvoyé ; un client n'est pas l'autorité.
        self.assertIs(self.anim('setGesture("lk-1", "aim")'), True)
        self.relay_tick()
        self.assertEqual(self.states(), [])
        refused = self.h.eval('A', '{ LivingKnox.Anim.setGesture("lk-1", "run") }')
        self.assertEqual(lua_list(refused), [False, 'not the authority (MP client)'])
        self.assertEqual(self.h.errors('A'), [])

    def test_idempotent_passes_and_recreated_copy_reapplied(self):
        zid = self.ready()
        self.anim('setGesture("lk-1", "guard")')
        self.relay_tick()
        self.h.pump()
        self.apply()
        before = self.h.eval('A', 'LivingKnox.Anim.stats.sets')
        self.apply(5)
        self.assertEqual(self.h.eval('A', 'LivingKnox.Anim.stats.sets'), before)  # rien de réécrit
        # Copie client recréée (5 s sans paquet) : nouvel objet sans variables, retrouvé par la garde.
        self.h.machine('A').H.removeZombie(zid)
        self.mirror(zid, machines=('A',))
        self.assertEqual(self.vars('A', zid), 'actor=nil gesture=nil')
        self.slow()
        self.apply()
        self.assertEqual(self.vars('A', zid), 'actor=true gesture=guard')

    def test_late_client_hello_and_older_tables_ignored(self):
        zid = self.ready()
        self.anim('setGesture("lk-1", "crouch")')
        self.relay_tick()
        self.h.pump()
        # Client B qui (ré)entre en partie : plus de liste ni de gestes ; sa demande guardHello reçoit les deux.
        self.h.load('B', 'LivingKnox.ZombieGuard.roster = { rev = -1, count = 0, byId = {}, byOnline = {} }\n'
                         'LivingKnox.ZombieGuard.cache = {}\nLivingKnox.ZombieGuard.state.hello = 0\n'
                         'LivingKnox.Anim.remote = { r = {}, g = {} }')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.h.pump(limit=1)
        self.relay_tick()
        answers = self.states()
        self.assertEqual([m['to'] for m in answers], ['B'])
        self.assertEqual(answers[0]['args']['d']['lk-1']['g'], 'crouch')
        self.h.pump()
        self.slow()
        self.apply()
        self.assertEqual(self.vars('B', zid), 'actor=true gesture=crouch')
        # Entrée plus ancienne livrée après une plus récente : ignorée ; plus récente sans geste ou { gone } : idle.
        r = self.h.eval('A', 'LivingKnox.Anim.remote.r["lk-1"]')
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'animState', {'d': {'lk-1': {'r': r - 1, 'g': 'run'}}})
        self.assertEqual(self.h.eval('A', 'LivingKnox.Anim.gestureOf("lk-1")'), 'crouch')
        self.assertEqual(self.h.eval('A', 'LivingKnox.Anim.stats.older'), 1)
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'animState', {'d': {'lk-1': {'r': r + 50, 'gone': True}}})
        self.apply()
        self.assertEqual(self.vars('A', zid), 'actor=true gesture=idle')
        # Retour à idle côté serveur : entrée effacée, geste idle envoyé aux deux clients.
        self.anim('setGesture("lk-1", "idle")')
        self.relay_tick()
        self.assertEqual([m['args']['d']['lk-1']['g'] for m in self.states()], ['idle', 'idle'])
        self.assertEqual(self.ev('LivingKnox.Anim.wanted["lk-1"]'), None)

    def test_invalid_requests_refused(self):
        self.ready()
        for code, why in (('setGesture("lk-1", "dance")', 'unknown gesture dance'),
                          ('setGesture("lk-1", nil)', 'unknown gesture nil'),
                          ('setGesture(3, "aim")', 'bad npc id 3')):
            self.assertEqual(lua_list(self.ev('{ LivingKnox.Anim.' + code + ' }')), [False, why])
        self.relay_tick()
        self.assertEqual(self.states(), [])


class SoloAnimTests(AnimBase):
    mode = 'solo'

    def test_solo_sets_variables_on_the_npc_only_and_clears_an_unbound_object(self):
        zid = self.npc()
        self.h.spawn_zombie(2000, 103, 102, 0)
        self.apply()
        self.assertEqual(self.vars('solo', zid), 'actor=true gesture=idle')
        self.assertIs(self.anim('setGesture("lk-1", "strike")'), True)
        self.assertEqual(self.h.pending(), [])
        self.apply()
        self.assertEqual(self.vars('solo', zid), 'actor=true gesture=strike')
        self.assertEqual(self.vars('solo', 2000), 'actor=nil gesture=nil')
        sets = self.ev('LivingKnox.Anim.stats.sets')
        self.apply(4)
        self.assertEqual(self.ev('LivingKnox.Anim.stats.sets'), sets)
        # Objet qui n'est plus le corps courant (encore vivant) : variables retirées.
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = nil')
        self.apply()
        self.assertEqual(self.vars('solo', zid), 'actor=nil gesture=nil')
        self.assertEqual(self.h.errors('solo'), [])

    def test_dev_command_and_suite(self):
        self.npc()
        self.h.load('solo', 'server/RST/RST_LKBodiesServer.lua')
        self.h.load('solo', 'client/RST/RST_LKBodiesClient.lua')
        self.assertIs(self.h.eval('solo', 'LKB.gesture(1, "aim")'), True)
        self.assertEqual(self.ev('LivingKnox.Anim.wanted["lk-1"]'), 'aim')
        self.assertIs(self.h.eval('solo', 'LKB.gesture(1, "dance")'), False)
        self.assertIs(self.h.eval('solo', 'LKB.gesture(9, "aim")'), False)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKB]')]
        self.assertIn('[LKB] gesture lk-1 -> aim (body bound)', lines)
        self.assertIn('[LKB] gesture refused: unknown gesture dance', lines)
        self.assertIn('[LKB] gesture refused: unknown npc lk-9', lines)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.anims", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.anims')
        self.assertEqual(lua_list(listed.tags), ['world'])
        self.assertIsNone(listed.error)

    def test_probe_parses_the_animation_debug_text(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKAnims.lua')
        # Texte de getAnimationDebug (AdvancedAnimator.GetDebug + AnimLayer.GetDebugString, 42.21.0).
        text = ('zombie123\\nGameState: ZombieIdleState\\nLayer: 0\\nState: zombie/idle\\n  Node: LKActorAimHandgun\\n'
                '  Node: LKActorIdle\\n  AnimTrack:\\n    Anim: Bob_IdleAimHandgun Weight: 0.8\\n'
                '    Anim: Bob_Idle Weight: 0.2\\nSubLayer: 0\\nState: zombie/hitreaction\\n  Node: Other\\n'
                'Variables:\\nWeapon: \\n')
        info = self.h.eval('solo', '(function() local z = { getAnimationDebug = function() return "' + text + '" end,'
                           ' getVariableBoolean = function() return true end, getVariableString = function() return '
                           '"aim" end, getActionStateName = function() return "idle" end }'
                           ' return RST.LKAnims.info(z) end)()')
        self.assertEqual((info.actor, info.gesture, info.action, info.state), (True, 'aim', 'idle', 'idle'))
        self.assertEqual(lua_list(info.nodes), ['LKActorAimHandgun', 'LKActorIdle'])
        self.assertEqual(lua_list(info.anims), ['Bob_IdleAimHandgun', 'Bob_Idle'])


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in MOD_FILES + DEV_FILES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')

    def test_variables_only_on_engine_bodies(self):
        code = (LUA / ANIM).read_text(encoding='utf-8')
        self.assertNotIn('getModData', code)  # solo : Bodies.bound ; client : copies retrouvées par la garde
        self.assertIn('isReanimatedPlayer()', code)
        # Mêmes noms que les conditions des nœuds générés.
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        self.assertIn(f'Anim.VAR_ACTOR = "{table["actorVariable"]}"', code)
        self.assertIn(f'Anim.VAR_GESTURE = "{table["gestureVariable"]}"', code)
        for g in table['gestures']:
            self.assertRegex(code, rf'\b{g} = true\b')


if __name__ == '__main__':
    unittest.main()
