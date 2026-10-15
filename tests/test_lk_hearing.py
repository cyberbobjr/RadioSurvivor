"""Tests hors jeu de LK06-T10 : un corps de PNJ ne réagit à aucun bruit (ni du monde ni des PNJ), les zombies vanilla
restent attirés par les bruits des PNJ. Code : shared/LivingKnox/LK_ZombieGuard.lua (useless gardé pendant un trajet),
bruits de server/LivingKnox/LK_Zombies.lua (pas, attrait ; source nil depuis LK06-T08).

    python RadioSurvivor/tests/test_lk_hearing.py

Constat en jeu du 2026-10-12 (lk.anims, PNJ lk-109 au geste walk) : 7 s dans l'état turnalerted, 0,52 case parcourue.
Banc tests/harness.py et pile de test_lk_zombies.py (corps, consignes, exécutant, garde, gestes, combat, santé), plus
la doublure RESPOND ci-dessous, qui reproduit IsoZombie.RespondToSound (Java 42.21.0) et NE PROUVE PAS l'API réelle :
- sorties (J/characters/IsoZombie.java:1306-1317) : ghost, useless, serveur (GameServer.server), copie distante d'un
  client ;
- bruit retenu : WorldSoundManager.getBiggestSoundZomb(x, y, z, ignoreBySameType = true) (J/WorldSoundManager.java:
  214-249) : source zombie ignorée (sourceIsZombie = source instanceof IsoZombie, posé par WorldSound.init ; nil ->
  faux), distance² entre la case du zombie (coordonnées entières, z x 3) et celle du bruit > (rayon x ouïe)² ignorée,
  plus fort volume x (1 - distance² / (rayon x ouïe)²) ; ouïe 1 (option « normale »), pièces ignorées (banc sans
  pièce) ;
- réaction (lignes 1373-1419) : délai Rand(0, 16) et décalage Rand(+-distance/2,5) pris à 0 ; zombie en marche vers
  une case (état pathfind ou walktoward) : bruit dans la même direction que le but (IsoUtils.isSimilarDirection, < 0,5,
  J/iso/IsoUtils.java:115-122) -> rien, sinon setTurnAlertedValues (alerted vrai, état turnalerted) et pathToSound (le
  but devient le bruit) ; zombie au repos : pathToSound, tourné s'il ne fait pas face (pris comme tourné) ;
- un bruit vit une image (WORLD_SOUNDS vidé après le passage).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_zombies import ZombieBase  # noqa: E402

GUARD = LUA / 'shared' / 'LivingKnox' / 'LK_ZombieGuard.lua'
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKAnims.lua'

HEARING_DOUBLES = r'''
local H = HARNESS
WORLD_SOUNDS, REACTIONS = {}, {}
local prevAdd = addSound
addSound = function(src, x, y, z, r, v)
    prevAdd(src, x, y, z, r, v)
    if r <= 0 then return end   -- WorldSoundManager.addSound : rayon nul -> aucun bruit
    WORLD_SOUNDS[#WORLD_SOUNDS + 1] = { x = x, y = y, z = z, r = r, v = v, zsrc = instanceof(src, 'IsoZombie') }
end
local function norm(x, y)
    local l = math.sqrt(x * x + y * y)
    if l == 0 then return 0, 0 end
    return x / l, y / l
end
-- IsoUtils.isSimilarDirection(chr, xA, yA, xB, yB, 0.5).
local function similar(zb, xa, ya, xb, yb)
    local ax, ay = norm(xa - zb.x, ya - zb.y)
    local bx, by = norm(zb.x - xb, zb.y - yb)
    local sx, sy = ax + bx, ay + by
    return math.sqrt(sx * sx + sy * sy) < 0.5
end
function RESPOND(zb)
    if zb:isUseless() then return 'useless' end
    if isServer() then return 'server' end
    if isClient() and zb:isRemoteZombie() then return 'remote' end
    local fx, fy, fz = math.floor(zb.x), math.floor(zb.y), math.floor(zb.z)
    local best, bestTot = nil, -1000000
    for _, s in ipairs(WORLD_SOUNDS) do
        if not s.zsrc then
            local dx, dy, dz = fx - s.x, fy - s.y, (fz - s.z) * 3
            local dist = dx * dx + dy * dy + dz * dz
            local radius = s.r
            if dist <= radius * radius then
                local delta = 1 - dist / (radius * radius)
                if delta > 0 and s.v * delta > bestTot then best, bestTot = s, s.v * delta end
            end
        end
    end
    if best == nil then return 'none' end
    local walking = zb.goal ~= nil and (zb:getVariableBoolean('bPathfind') or zb.moving == true)
    if walking and similar(zb, best.x, best.y, zb.goal.x + 0.5, zb.goal.y + 0.5) then return 'ahead' end
    zb.animVars = rawget(zb, 'animVars') or {}
    zb.animVars.alerted = true
    zb.actionState = 'turnalerted'
    zb.goal = { x = best.x, y = best.y, z = best.z }   -- pathToSound
    REACTIONS[#REACTIONS + 1] = { id = zb.onlineID, x = best.x, y = best.y }
    return 'turned'
end
-- Une image de réaction au bruit pour tous les zombies de cette machine, puis bruits oubliés.
function RESPOND_ALL()
    local out = {}
    for _, zb in ipairs(H.zombieList.items) do
        if not zb:isDead() then out[zb.onlineID] = RESPOND(zb) end
    end
    WORLD_SOUNDS = {}
    return out
end
function REACTED(id)
    local n = 0
    for _, r in ipairs(REACTIONS) do
        if r.id == id then n = n + 1 end
    end
    return n
end
'''


class HearingBase(ZombieBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, HEARING_DOUBLES)
        return h

    def frames(self, ticks, walkers=()):
        """ticks images : tick, pas de marche des zombies walkers (machine qui simule), réaction au bruit."""
        for _ in range(ticks):
            self.h.tick(1)
            for zid in walkers:
                self.h.eval(self.sim(zid), f'STEP({zid}, 0.05)')
            for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
                self.h.eval(m, 'RESPOND_ALL()')
            if self.mode == 'mp':
                self.h.pump()

    def reacted(self, zid, m=None):
        return self.h.eval(m or self.srv, f'REACTED({zid})')


class SoloHearingTests(HearingBase):
    mode = 'solo'

    def test_walking_body_never_hears_its_own_steps_even_when_travelling(self):
        # Reproduction du constat : drapeau de trajet posé (ce que faisait la suite lk.anims), geste walk. Ancien code :
        # useless levé, le corps entend son pas émis sur sa case (derrière lui) et se retourne vers lui.
        zid = self.npc()
        self.npc_zid = zid
        # Marche de la suite lk.anims, sans consigne (une consigne ferme le trajet, LK_Directives endServerRun) : geste
        # walk, drapeau de trajet, chemin en état pathfind comme LK_Executor.issuePath.
        self.assertIs(self.ev('LivingKnox.Anim.setGesture("lk-1", "walk")'), True)
        self.assertIs(self.ev('LivingKnox.ZombieGuard.setTravelling("lk-1", true)'), True)
        self.run_lua(f'local z = HARNESS.zombies[{zid}]; z:pathToLocation(111, 102, 0); '
                     'z:setVariable("bPathfind", true); z:setMoving(false)')
        self.frames(int(4000 / self.h.tick_ms), walkers=(zid,))
        body = self.h.zombie('solo', zid)
        self.assertGreater(self.zstat('steps'), 0)                       # pas émis, source nil
        self.assertIs(self.ev('NOISES[1].src == nil'), True)
        self.assertEqual(self.reacted(zid), 0)
        self.assertIs(body.useless, True)
        self.assertNotEqual(body.actionState, 'turnalerted')
        self.assertGreater(body.x, 105)                                  # il marche (état pathfind, useless gardé)
        self.assertEqual((body.goal.x, body.goal.y), (111, 102))         # but de la consigne, jamais un bruit

    def test_vanilla_zombie_still_comes_to_the_npc_steps(self):
        zid = self.npc()
        self.npc_zid = zid
        vz = self.vanilla(8201, 0, 5)                                    # au repos, 5 cases au sud du départ
        self.run_lua(f'HARNESS.zombies[{vz}].fakeDead = false')
        self.assertEqual(self.d('moveTo("lk-1", 108, 102, 0, "walk")'), 1)
        self.frames(int(3000 / self.h.tick_ms), walkers=(zid,))
        self.assertGreater(self.reacted(vz), 0)                          # pas du PNJ (rayon 7) entendus
        self.assertEqual(self.reacted(zid), 0)
        goal = self.h.zombie('solo', vz).goal
        self.assertIsNotNone(goal)
        self.assertEqual(goal.y, 102)                                    # il part vers la ligne du PNJ

    def test_bodies_ignore_world_and_npc_noises_at_rest_and_walking(self):
        zid = self.npc()
        self.npc_zid = zid
        second = self.spawn(105, 106)[1].onlineID                        # second PNJ, au repos
        vz = self.vanilla(8301, 3, 3)
        self.assertEqual(self.d('moveTo("lk-1", 111, 102, 0, "run")'), 1)
        self.frames(30, walkers=(zid,))
        player = 'getPlayer()'
        for code in (f'addSound({player}, 103, 103, 0, 30, 30)',           # bruit d'un joueur (monde)
                     'addSound(nil, 100, 102, 0, 30, 30)',                 # cri ou tir d'un PNJ (source nil)
                     f'addSound(HARNESS.zombies[{second}], 104, 104, 0, 30, 30)'):   # source zombie
            self.run_lua(code)
            self.frames(1, walkers=(zid,))
        self.assertEqual(self.reacted(zid), 0)
        self.assertEqual(self.reacted(second), 0)
        self.assertGreater(self.reacted(vz), 0)
        for z in (zid, second):
            self.assertIs(self.h.zombie('solo', z).useless, True)


class MultiplayerHearingTests(HearingBase):
    def test_owner_client_keeps_the_travelling_body_deaf_and_the_server_never_reacts(self):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.move_player('A', srv.x + 8, srv.y)
        self.h.move_player('B', srv.x + 9, srv.y)
        self.assertIs(self.ev('LivingKnox.ZombieGuard.setTravelling("lk-1", true)'), True)
        for _ in range(3):
            self.slow()
            self.h.pump()
        self.assertIs(self.h.eval('A', 'LivingKnox.ZombieGuard.isTravelling("lk-1")'), True)   # t = vrai reçu
        self.assertIs(self.h.zombie('A', zid).useless, True)
        self.h.eval('A', f'addSound(nil, {int(srv.x) - 3}, {int(srv.y)}, 0, 20, 20)')
        out = self.h.eval('A', 'RESPOND_ALL()')
        self.assertEqual(out[zid], 'useless')
        self.h.eval('server', f'addSound(nil, {int(srv.x) - 3}, {int(srv.y)}, 0, 20, 20)')
        # Serveur : RespondToSound sort toujours (useless reste de la création, sinon GameServer.server).
        self.assertIn(self.h.eval('server', 'RESPOND_ALL()')[zid], ('useless', 'server'))
        self.assertEqual(self.h.eval('B', 'RESPOND_ALL()')[zid], 'remote')        # copie non simulée : sort aussi
        self.assertEqual(self.reacted(zid, 'A'), 0)


class SourceTests(unittest.TestCase):
    def test_guard_keeps_useless_whatever_the_travel_flag(self):
        code = GUARD.read_text(encoding='utf-8')
        self.assertFalse('not travelling' in code, 'useless still follows the travel flag')
        self.assertTrue('z:setUseless(true)' in code)
        self.assertFalse('setUseless(false)' in code)

    def test_anims_suite_walks_like_the_executor_and_checks_alerts(self):
        code = SUITE.read_text(encoding='utf-8')
        self.assertNotIn('setTravelling(id, true)', code)
        self.assertIn('z:setVariable("bPathfind", true)', code)
        self.assertIn('"alerted"', code)
        self.assertIn('turnalerted', code)


if __name__ == '__main__':
    unittest.main()
