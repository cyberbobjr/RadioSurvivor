"""Tests hors jeu de LK06-T09 (offensive à la fenêtre : un PNJ ouvre la fenêtre que tape un zombie, le zombie
l'enjambe et tombe à l'intérieur, les PNJ l'achèvent au sol) : server/LivingKnox/LK_Defense.lua (choix et conduite
de l'offensive, bascule de la fenêtre à l'instant du geste), LK_Combat.lua (geste de coup au sol), LK_Zombies.lua
(dégâts au sol, réaction « Floor »), client/LivingKnox/LK_CombatClient.lua (minutage des gestes au sol) et
client/LivingKnox/LK_ZombiesClient.lua (réaction posée par le client qui simule le zombie).

    python RadioSurvivor/tests/test_lk_window_kill.py

Bancs :
- logique pure (choix de la fenêtre et de l'ouvreur, rapport de forces, jamais en repli) ;
- pile de test_lk_zombies.py (solo et serveur + deux clients) : geste et dégâts du coup au sol ;
- pile complète de test_lk_defense.py (groupe « deciders » dans la maison HOUSE, bâtiment 105..115), complétée des
  doublures ci-dessous, qui reproduisent le Java 42.21.0 relevé et NE PROUVENT PAS l'API réelle :
  - fenêtre du mur ouest posée sur la case 105,110 (bord ouest ; dehors 104,110), verrouillée au départ : IsOpen,
    isDestroyed, isBarricaded, isPermaLocked, getNorth, getObjectIndex, ToggleWindow (déverrouille et bascule,
    IsoWindow.java:701-731) ; getWindowTo / isWindowBlockedTo du bord commun ;
  - LosUtil.lineClear : à travers le mur ouest sur la rangée 110 = ClearThroughWindow (vitre, même fermée), ailleurs
    à travers un mur du bâtiment = Blocked ;
  - zombie qui frappe la fenêtre (getThumpTarget, état « thump ») et, fenêtre ouverte, l'enjambe et tombe à
    l'intérieur (ThumpState.java:183-193, ClimbThroughWindowState.java:105-127, 296-308 : CLIMB_MS puis à terre
    DOWN_MS), réaction « Floor » qui le garde à terre REACT_MS de plus (CombatManager.java:2410-2436,
    ZombieOnGroundState.startReanimateTimer : 30 à 89 images), puis relevé ;
  - IsoZombie.setHitReaction / getHitReaction, HandWeapon.getCriticalDamageMultiplier.
- LK06-T11 : cible des coups d'un zombie simulé par un client, rapportée par le client qui le simule (commande
  zombieThumps, LK_Senses.lua) et contrôlée par le serveur (zombie connu, fenêtre réelle, copie à portée, foyer,
  fraîcheur) ; aucune déduction par la proximité d'une vitre ; refermeture de la fenêtre après l'offensive (geste
  closewindow, embrasure libre) ; collecte chez le propriétaire et transport : tests/test_lk_senses.py
  (ThumpReportTests).
- suite en jeu lk.windowkill : chargée et listée (son déroulé demande le moteur réel).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import DEV_LUA, LUA, lua_list  # noqa: E402
from test_lk_defense import DefenseStack, PureDefenseBase  # noqa: E402
from test_lk_zombies import ZombieBase  # noqa: E402

Df = 'LivingKnox.Defense'
Z = 'LivingKnox.Zombies'
SUITE_FILE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKWindowKill.lua'
MOD_FILES = [LUA / 'server/LivingKnox/LK_Defense.lua', LUA / 'server/LivingKnox/LK_Combat.lua',
             LUA / 'server/LivingKnox/LK_Zombies.lua', LUA / 'client/LivingKnox/LK_CombatClient.lua',
             LUA / 'client/LivingKnox/LK_ZombiesClient.lua']

# Réaction et multiplicateur critique (pile de combat).
FLOOR_DOUBLES = r'''
local C = HARNESS.classes
local Zc = C.IsoZombie
function Zc:setHitReaction(r)
    if type(r) ~= 'string' then error('No implementation found for setHitReaction', 2) end
    self.hitReaction = r
    REACTIONS = (REACTIONS or 0) + 1
end
function Zc:getHitReaction() return self.hitReaction or '' end
CRIT = { ['Base.BaseballBat'] = 2.0 }
function C.HandWeapon:getCriticalDamageMultiplier() return CRIT[self.t] or 2.0 end
'''

# Fenêtre ouest de la maison HOUSE, vue, coups et chute du zombie (voir l'en-tête).
WINDOW_KILL_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Sq = C.IsoGridSquare
if Sq.TreatAsSolidFloor == nil then function Sq:TreatAsSolidFloor() return true end end
function C.IsoZombie:getThumpTarget() return self.thump end
local Win = C.IsoWindow
function Win:IsOpen() return self.open == true end
function Win:isDestroyed() return self.destroyed == true end
function Win:isBarricaded() return (self.planks or 0) > 0 end
function Win:isPermaLocked() return self.permaLocked == true end
function Win:isLocked() return self.locked == true end
function Win:getNorth() return self.north == true end
function Win:getSquare() return self.square end
function Win:getObjectIndex() return self.removed and -1 or 3 end
TOGGLES = {}
function Win:ToggleWindow(chr)
    if chr ~= nil and getmetatable(chr) ~= C.IsoZombie then error('No implementation found for ToggleWindow', 2) end
    TOGGLES[#TOGGLES + 1] = chr
    if self.permaLocked or self.destroyed then return end
    self.locked = false
    self.open = not self.open
end
WIN = setmetatable({ square = H.square(105, 110, 0), north = false, locked = true }, Win)
local function isWin(a, b)
    return b ~= nil and a.y == 110 and b.y == 110 and a.z == 0 and b.z == 0
        and ((a.x == 104 and b.x == 105) or (a.x == 105 and b.x == 104))
end
local getWin = Sq.getWindowTo
function Sq:getWindowTo(nb)
    if isWin(self, nb) then return WIN end
    return getWin(self, nb)
end
local blocked = Sq.isWindowBlockedTo
function Sq:isWindowBlockedTo(nb)
    if isWin(self, nb) then return (not WIN.open and not WIN.destroyed) or (WIN.planks or 0) > 0 end
    return blocked(self, nb)
end
local function inside(x, y) return x >= 105 and x <= 115 and y >= 105 and y <= 115 end
LosUtil = { lineClear = function(cell, x0, y0, z0, x1, y1, z1, ignoreDoors)
    for _, v in ipairs({ x0, y0, z0, x1, y1, z1 }) do
        H.num(v, 'LosUtil.lineClear')
        if v ~= math.floor(v) then error('LosUtil.lineClear: int expected, got ' .. v, 2) end
    end
    if type(ignoreDoors) ~= 'boolean' then error('No implementation found for LosUtil.lineClear', 2) end
    local r = 'Clear'
    if inside(x0, y0) ~= inside(x1, y1) then
        if y0 == 110 and y1 == 110 and math.min(x0, x1) <= 104 and math.max(x0, x1) >= 105 then
            r = 'ClearThroughWindow'
        else
            r = 'Blocked'
        end
    end
    return setmetatable({}, { __tostring = function() return r end })
end }
-- Zombie qui frappe WIN puis, ouverte, l'enjambe et tombe à l'intérieur (temps réel du banc).
CLIMB_MS, DOWN_MS, REACT_MS = 900, 2050, 2000
CLIMBS, FLOOR_REACTIONS, GOT_UP = 0, 0, 0
function THUMPER(zid)
    local zb = H.zombies[zid]
    zb.thump = WIN
    zb.actionState = 'thump'
    zb.model = true
    return zb
end
Events.OnTick.Add(function()
    local t = getTimestampMs()
    for _, zb in ipairs(H.zombieList.items) do
        if zb.model and not zb:isDead() then
            if zb.thump == WIN and (WIN.open or WIN.destroyed) then
                zb.thump = nil
                zb.actionState = 'climbwindow'
                zb.climbAt = t
            elseif zb.actionState == 'climbwindow' and t - zb.climbAt >= CLIMB_MS then
                H.place(zb, 105.5, 110.5, 0)
                zb.actionState = 'onground'
                zb.onFloor = true
                zb.upAt = t + DOWN_MS
                CLIMBS = CLIMBS + 1
            elseif zb.onFloor then
                if zb.hitReaction == 'Floor' then
                    zb.hitReaction = nil
                    zb.upAt = t + REACT_MS
                    FLOOR_REACTIONS = FLOOR_REACTIONS + 1
                end
                if t >= zb.upAt then
                    zb.onFloor = false
                    zb.actionState = 'idle'
                    GOT_UP = GOT_UP + 1
                end
            end
        end
    end
end)
'''


class ChooseOffenseTests(PureDefenseBase):
    def lst(self, code):
        return list(self.run_lua(code))

    def choose(self, phase, cands):
        return list(self.run_lua(f'local c, why = {Df}.chooseOffense({phase}, {cands}) '
                                 'if c == nil then return nil, why end return c.key, c.mid, c.waiting, c.helpers'))

    def test_nearest_able_member_opens_when_the_ratio_holds(self):
        cands = ('{ { key = "105,110,0,W", waiting = 1, helpers = { { mid = "m-3", number = 3, d = 0.5 }, '
                 '{ mid = "m-1", number = 1, d = 2.0 } } } }')
        self.assertEqual(self.choose('"hold"', cands), ['105,110,0,W', 'm-3', 1, 2])
        # Égalité de distance : numéro de membre.
        cands = ('{ { key = "k", waiting = 2, helpers = { { mid = "m-3", number = 3, d = 1 }, '
                 '{ mid = "m-2", number = 2, d = 1 } } } }')
        self.assertEqual(self.choose('"hold"', cands)[1], 'm-2')

    def test_never_when_overwhelmed_or_outnumbered_at_the_window(self):
        one = '{ { key = "k", waiting = 1, helpers = { { mid = "m-1", number = 1, d = 1 } } } }'
        self.assertEqual(self.choose('"withdraw"', one), [None, 'group overwhelmed (withdraw)'])
        self.assertEqual(self.choose('nil', one)[0], None)
        two = '{ { key = "k", waiting = 2, helpers = { { mid = "m-1", number = 1, d = 1 } } } }'
        self.assertEqual(self.choose('"hold"', two),
                         [None, 'window k: 2 zombie(s) waiting > 1 x 1 able member(s)'])
        nobody = '{ { key = "k", waiting = 1, helpers = {} } }'
        self.assertEqual(self.choose('"hold"', nobody), [None, 'window k: no able member near it'])
        self.assertEqual(self.choose('"hold"', '{}'), [None, 'no window thumped'])

    def test_least_besieged_window_first(self):
        cands = ('{ { key = "a", waiting = 2, helpers = { { mid = "m-1", number = 1, d = 1 }, '
                 '{ mid = "m-2", number = 2, d = 1 } } }, '
                 '{ key = "b", waiting = 1, helpers = { { mid = "m-3", number = 3, d = 1 } } } }')
        self.assertEqual(self.choose('"hold"', cands)[:2], ['b', 'm-3'])

    def test_window_edge_and_facing_match_the_obstacles_convention(self):
        # Fenêtre posée sur sa case, bord ouest (W) ou nord (N) ; regard vers l'autre côté.
        e = self.lst(f'local w = {{ getSquare = function() return HARNESS.square(105, 110, 0) end, '
                         f'getNorth = function() return false end }} local e = {Df}.windowEdge(w) '
                         f'return e.key, e.ax, e.bx, e.mx, e.my, {Df}.faceWindow(e, 105.5, 110.5), '
                         f'{Df}.faceWindow(e, 104.5, 110.5)')
        self.assertEqual(e, ['105,110,0,W', 104, 105, 105, 110.5, 180, 0])
        e = self.lst(f'local w = {{ getSquare = function() return HARNESS.square(112, 105, 0) end, '
                         f'getNorth = function() return true end }} local e = {Df}.windowEdge(w) '
                         f'return e.key, e.ay, e.by, e.mx, e.my, {Df}.faceWindow(e, 112.5, 105.5)')
        self.assertEqual(e, ['112,105,0,N', 104, 105, 112.5, 105, 270])


class FloorStrikeTests(ZombieBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', FLOOR_DOUBLES)
        return h

    def down(self, zid, down=True, crawling=False):
        self.run_lua(f'HARNESS.zombies[{zid}].onFloor = {str(down).lower()} '
                     f'HARNESS.zombies[{zid}].crawling = {str(crawling).lower()}')

    def test_floor_gesture_by_weapon_and_standing_or_crawling_zombie(self):
        self.npc_zid = self.npc()
        zid = self.vanilla(8201, 1.0, 0, health=50.0)
        self.down(zid)
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'stomp')       # mains nues : piétinement
        self.down(zid, False)
        self.c('step("lk-1")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'strike')      # debout
        self.down(zid, True, crawling=True)
        self.c('step("lk-1")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'strike')      # rampant : frappé debout
        self.c('disengage("lk-1", "test")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        self.down(zid)
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 2)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'strikefloor')  # arme visée au sol
        self.c('disengage("lk-1", "test")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')        # geste au sol retiré aussi

    def test_floor_damage_follows_the_vanilla_floor_attack(self):
        self.npc_zid = self.npc()

        def dmg(t, hits, floor):
            return self.z(f'damageOf("lk-1", {{ c = 1 }}, instanceItem("{t}"), {hits}, {str(floor).lower()})')
        roll = self.ev('LivingKnox.Combat.roll("lk-1", 1, 1001)')
        level = 1.5 * (0.3 + 3 * 0.1)
        bat = 0.8 + (1.1 - 0.8) * roll / 99
        self.assertAlmostEqual(dmg('Base.BaseballBat', 1, False), bat * level * 0.15, places=9)
        # Arme visée au sol : x max(5, critique 2).
        self.assertAlmostEqual(dmg('Base.BaseballBat', 1, True), bat * level * 5 * 0.15, places=9)
        self.run_lua('CRIT["Base.BaseballBat"] = 7')
        self.assertAlmostEqual(dmg('Base.BaseballBat', 1, True), bat * level * 7 * 0.15, places=9)
        # Mains nues au sol : piétinement Rand(0,7, 1,0) + Force 5 x 0,2, chaussures 1,0, sans le x 5.
        stomp = 0.7 + 0.3 * roll / 99 + 5 * 0.2
        self.assertAlmostEqual(dmg('Base.BareHands', 1, True), stomp * level * 0.15, places=9)
        # Dès le 4e coup de mêlée : x (coups - 2) x 1,5, au sol comme debout.
        roll4 = self.ev('LivingKnox.Combat.roll("lk-1", 1, 1004)')
        stomp4 = 0.7 + 0.3 * roll4 / 99 + 1.0
        self.assertAlmostEqual(dmg('Base.BareHands', 4, True), stomp4 * level * 3 * 0.15, places=9)
        # Arme à feu : aucun effet du sol.
        self.assertAlmostEqual(dmg('Base.Pistol', 1, True), dmg('Base.Pistol', 1, False), places=12)

    def test_floor_hit_keeps_the_zombie_down_and_is_applied_once(self):
        self.npc_zid = self.npc()
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        zid = self.vanilla(8202, 1.0, 0, health=50.0)
        self.down(zid)
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        for _ in range(20):
            self.seconds(0.5)
            if self.zstat('hits') >= 2:
                break
        hits = self.zstat('hits')
        self.assertGreaterEqual(hits, 2)                                 # impacts minutés sur le geste au sol
        self.assertEqual(self.zstat('floorHits'), hits)
        self.assertEqual(self.c('stats.applied'), hits)
        self.assertEqual(self.ev('REACTIONS'), hits)                     # réaction « Floor » à chaque coup
        self.assertEqual(self.ev(f'HARNESS.zombies[{zid}].hitReaction'), 'Floor')
        dealt = sum(self.z(f'damageOf("lk-1", {{ c = 1 }}, instanceItem("Base.BaseballBat"), {k}, true)')
                    for k in range(1, hits + 1))
        self.assertAlmostEqual(self.health(zid), 50.0 - dealt, places=6)
        # Debout : coup ordinaire, aucune réaction posée.
        self.run_lua(f'HARNESS.zombies[{zid}].hitReaction = nil REACTIONS = 0')
        self.down(zid, False)
        before = self.zstat('hits')
        for _ in range(20):
            self.seconds(0.5)
            if self.zstat('hits') > before:
                break
        self.assertGreater(self.zstat('hits'), before)
        self.assertEqual(self.ev('REACTIONS'), 0)
        self.assertEqual(self.zstat('floorHits'), hits)

    def test_zombie_killed_on_the_floor(self):
        self.npc_zid = self.npc()
        zid = self.vanilla(8203, 1.0, 0, health=1.0)
        self.down(zid)
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        for _ in range(40):
            self.seconds(0.5)
            if self.h.zombie('solo', zid).killDone:
                break
        self.assertTrue(self.h.zombie('solo', zid).killDone)
        self.assertEqual(self.zstat('kills'), 1)
        self.assertTrue(any('killed zombie' in line and 'on the floor' in line for line in self.lk()), self.lk()[-5:])


class FloorReactionMultiplayerTests(ZombieBase):
    def make(self, root=None):
        h = super().make(root)
        for m in ('server', 'A', 'B'):
            h.load(m, FLOOR_DOUBLES)
        return h

    def test_reaction_sent_to_the_client_that_simulates_the_zombie(self):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.move_player('A', srv.x + 8, srv.y)
        self.h.move_player('B', srv.x + 9, srv.y)
        self.npc_zid = zid
        z = self.vanilla(8301, 1.0, 0, owner='B', health=5.0)
        for m in ('server', 'A', 'B'):
            self.h.eval(m, f'(function() HARNESS.zombies[{z}].onFloor = true return true end)()')
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        ok = self.run_lua(f'local o = {{ c = 1 }} return (LivingKnox.Zombies.hurt("lk-1", o, HARNESS.zombies[{z}], '
                          'instanceItem("Base.BaseballBat")))')
        self.assertIs(ok, True)
        self.assertEqual(self.ev(f'HARNESS.zombies[{z}].hitReaction'), 'Floor')       # copie du serveur
        self.h.pump()
        self.assertEqual(self.h.eval('B', f'HARNESS.zombies[{z}].hitReaction'), 'Floor')   # client qui le simule
        self.assertIsNone(self.h.eval('A', f'HARNESS.zombies[{z}].hitReaction'))
        self.assertLess(self.health(z, 'B'), 5.0)
        # Réaction inconnue : ignorée.
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'zombieHurt', {'o': z, 'd': 0.1, 'r': 'Shot'})
        self.assertEqual(self.h.eval('B', 'REACTIONS'), 1)


class WindowKillStack(DefenseStack):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, FLOOR_DOUBLES)
            h.load(m, WINDOW_KILL_DOUBLES)
        return h

    def thumpers(self, n=1):
        spots = [(104, 110), (103, 110), (104, 111)][:n]
        ids = self.horde(spots)
        for zid in ids:
            self.run_lua(f'THUMPER({zid})')
        return ids

    def fine(self, seconds, walk=1.0):
        """Pas de 250 ms (décisions une fois par seconde, combat et exécutant à chaque pas), marche de walk case/s."""
        every = self.ev('LivingKnox.Executor.EXEC_EVERY')
        for _ in range(int(seconds * 4)):
            self.run_lua(f'STEP_ALL({walk / 4})')
            self.h.advance_ms(250)
            self.h.tick(every)

    def offense(self, gid):
        out = self.run_lua(f'local st = {Df}.state.groups["{gid}"] local o = st and st.offense '
                           'if o == nil then return nil end return o.key, o.mid, o.state')
        return None if out is None else list(out)

    def group_log(self, gid):
        return lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                                     'if e.kind == "defense" then out[#out + 1] = e.text end end return out'))

    def to_the_kill(self, gid, z):
        """Offensive jusqu'à la mort du zombie z (fenêtre ouverte, chute, coups au sol)."""
        for _ in range(240):
            self.fine(0.25)
            if self.h.zombie('solo', z).killDone:
                return True
        return False

    def until_over(self, gid, steps=160):
        for _ in range(steps):
            self.fine(0.25)
            if self.offense(gid) is None:
                return True
        return False


class WindowKillTests(WindowKillStack):
    def test_window_opened_zombie_falls_inside_and_is_finished_on_the_floor(self):
        gid = self.mk()
        self.jump_to(11)
        z = self.thumpers(1)[0]
        self.dpass(3)
        phase, places, zombies, _ = self.plan(gid)
        self.assertEqual((phase, zombies), ('hold', 1))
        self.assertIn('m-1=post 105,110,0', places)                      # poste de la fenêtre frappée
        key, mid, state = self.offense(gid)
        # Ouvreur : le défenseur posté à cette fenêtre (combattant valide), compté avec le combattant proche.
        self.assertEqual((key, mid, state), ('105,110,0,W', 'm-1', 'opening'))
        self.assertTrue(any('window offensive at 105,110,0,W: m-1 opens it, 1 zombie(s) waiting' in t
                            for t in self.group_log(gid)), self.group_log(gid))
        self.assertFalse(self.ev('WIN.open'))
        opener = self.npc_of(gid, 'm-1')
        seen_act = False
        for _ in range(80):
            self.fine(0.25)
            if self.ev(f'LivingKnox.Anim.shownOf("{opener}")') == 'openwindow' and not self.ev('WIN.open'):
                seen_act = True                                       # geste du joueur avant la bascule
            if self.ev('CLIMBS') >= 1:
                break
        self.assertTrue(seen_act)
        self.assertEqual(self.ev(f'{Df}.stats.offenseGestures'), 1)
        self.assertEqual(self.ev(f'{Df}.stats.windowsOpened'), 1)
        self.assertEqual(self.ev('#TOGGLES'), 1)                          # une seule bascule
        self.assertIs(self.ev(f'rawequal(TOGGLES[1], LivingKnox.Bodies.find("{opener}"))'), True)
        self.assertTrue(self.ev('WIN.open'))
        self.assertFalse(self.ev('WIN.locked'))                           # ouverte de l'intérieur, déverrouillée
        self.assertEqual(self.ev('CLIMBS'), 1)                            # le zombie est tombé à l'intérieur
        self.assertEqual(self.offense(gid)[2], 'open')
        self.fine(1)
        self.assertEqual(self.ev(f'{Df}.get("{gid}").offense.state'), 'open')
        self.assertEqual(self.place_of(gid, 'm-1'), 'post 106,110,0')     # recul d'un pas : case de chute libre
        killed = False
        for _ in range(160):
            self.fine(0.25)
            if self.h.zombie('solo', z).killDone:
                killed = True
                break
        self.assertTrue(killed, self.lk()[-15:])
        self.assertGreaterEqual(self.ev(f'{Z}.stats.floorHits'), 1)
        self.assertGreaterEqual(self.ev('FLOOR_REACTIONS'), 1)            # gardé à terre par les coups au sol
        self.assertEqual(self.ev('GOT_UP'), 0)                            # achevé sans s'être relevé
        self.assertTrue(any('on the floor' in line and 'killed zombie' in line for line in self.lk()), self.lk()[-8:])
        self.assertTrue(any('opened the window' in t for t in self.group_log(gid)))
        # LK06-T11 : plus aucun zombie près d'elle : l'ouvreur referme la fenêtre par le geste du joueur.
        closing = False
        for _ in range(160):
            self.fine(0.25)
            off = self.offense(gid)
            if off is not None and off[2] == 'closing':
                closing = True
                self.assertEqual(off[1], 'm-1')                           # l'ouvreur referme
                if self.ev(f'LivingKnox.Anim.shownOf("{opener}")') == 'closewindow':
                    self.assertTrue(self.ev('WIN.open'))                  # geste avant la bascule
            if off is None:
                break
        self.assertTrue(closing)
        self.assertIsNone(self.offense(gid))
        self.assertFalse(self.ev('WIN.open'))                             # refermée
        self.assertEqual(self.ev('#TOGGLES'), 2)                          # ouverture puis fermeture, une fois chacune
        self.assertIs(self.ev(f'rawequal(TOGGLES[2], LivingKnox.Bodies.find("{opener}"))'), True)
        self.assertEqual(self.ev(f'{Df}.stats.closeGestures'), 1)
        self.assertEqual(self.ev(f'{Df}.stats.windowsClosed'), 1)
        log = self.group_log(gid)
        self.assertTrue(any('105,110,0,W: no zombie left at the window, m-1 closes the window' in t for t in log), log)
        self.assertTrue(any('m-1 closed the window' in t for t in log), log)
        self.assertTrue(any('over: window closed (no zombie left at the window)' in t for t in log), log)
        self.assertEqual(self.h.errors('solo'), [])

    def climb_watch(self, gid, z, steps=120):
        """Pas de 250 ms jusqu'à la mort de z ; rend (coups ou ordres sur z avant sa chute, chute vue, mort)."""
        key = f'z:{z}'
        before, fell = 0, False
        for _ in range(steps):
            self.fine(0.25)
            zb = self.h.zombie('solo', z)
            if zb.killDone:
                return before, fell, True
            if zb.onFloor:
                fell = True
            if not fell and self.ev('WIN.open'):
                hits = self.ev(f'{Z}.stats.hits') or 0
                orders = self.run_lua(f'local n = 0 for _, o in pairs(LivingKnox.Combat.orders) do '
                                      f'if o.u == "{key}" then n = n + 1 end end return n')
                before = max(before, hits + orders)
        return before, fell, False

    def test_climbing_zombie_is_not_hit_before_its_fall_then_hit_on_the_floor(self):
        """Demande du 2026-10-15 (campagne MP : zombie frappé debout pendant qu'il enjambait, achevé sans coup au
        sol) : aucun coup ni ordre de combat sur le zombie de l'offensive tant qu'il enjambe ; au sol : coup au sol."""
        gid = self.mk()
        self.jump_to(11)
        self.run_lua('CLIMB_MS = 5000')                                   # enjambée lente, défenseurs à 2 cases
        z = self.thumpers(1)[0]
        self.dpass(3)
        self.assertEqual(self.offense(gid)[2], 'opening')
        before, fell, killed = self.climb_watch(gid, z)
        self.assertTrue(fell)
        self.assertTrue(killed, self.lk()[-15:])
        self.assertEqual(before, 0)                                       # aucun coup avant la chute
        self.assertGreaterEqual(self.ev(f'{Z}.stats.floorHits'), 1)
        self.assertEqual(self.ev(f'{Z}.stats.hits'), self.ev(f'{Z}.stats.floorHits'))   # tous les coups au sol
        self.assertGreaterEqual(self.ev(f'{Df}.stats.offenseHeld'), 1)
        self.assertTrue(any(f'zombie z:{z} left alone until it falls inside' in line for line in self.lk()))
        self.assertTrue(any(f'zombie z:{z} on the floor, members may hit it' in line for line in self.lk()))
        self.assertEqual(self.h.errors('solo'), [])

    def test_without_the_hold_the_climbing_zombie_is_hit_standing(self):
        """Témoin : retenue coupée (OFFENSE_HOLD faux), le même déroulé frappe le zombie debout (défaut du MP)."""
        gid = self.mk()
        self.jump_to(11)
        self.run_lua(f'CLIMB_MS = 5000 {Df}.CFG.OFFENSE_HOLD = false')
        try:
            z = self.thumpers(1)[0]
            self.dpass(3)
            before, _, _ = self.climb_watch(gid, z)
            self.assertGreaterEqual(before, 1)
        finally:
            self.run_lua(f'{Df}.CFG.OFFENSE_HOLD = true')

    def test_zombie_that_comes_in_standing_is_fought_normally(self):
        """Zombie entré debout (aucune chute) : retenue levée après OFFENSE_STAND_MS, combat normal."""
        gid = self.mk()
        self.jump_to(11)
        self.run_lua('CLIMB_MS = 1e9')                                    # le modèle ne le fait jamais tomber
        z = self.thumpers(1)[0]
        self.dpass(3)
        for _ in range(80):
            self.fine(0.25)
            if self.ev('WIN.open'):
                break
        self.assertTrue(self.ev('WIN.open'))
        self.fine(1)
        # Il entre debout, sans enjamber (le banc le pose à l'intérieur, état idle).
        self.run_lua(f'local zb = HARNESS.zombies[{z}] zb.model = false zb.actionState = "idle" '
                     'HARNESS.place(zb, 106.5, 111.5, 0)')
        engaged = False
        for _ in range(40):
            self.fine(0.25)
            if self.run_lua(f'for _, o in pairs(LivingKnox.Combat.orders) do if o.u == "z:{z}" then return true end '
                            'end return false'):
                engaged = True
                break
        self.assertTrue(engaged, self.lk()[-15:])
        self.assertTrue(any(f'zombie z:{z} came in standing' in line for line in self.lk()), self.lk()[-15:])
        self.assertEqual(self.h.errors('solo'), [])

    def test_window_not_closed_on_someone_in_its_squares(self):
        """LK06-T11 : personnage (ici le joueur A) sur une case du bord : pas de fermeture ; libre : fermée ;
        toujours occupée : laissée ouverte après OFFENSE_CLOSE_MS."""
        gid = self.mk()
        self.jump_to(11)
        z = self.thumpers(1)[0]
        self.dpass(3)
        self.assertTrue(self.to_the_kill(gid, z), self.lk()[-15:])
        self.h.move_player('A', 104.5, 110.5)                           # dans l'embrasure, côté dehors
        for _ in range(24):
            self.fine(0.25)
        self.assertTrue(self.ev('WIN.open'))
        self.assertEqual(self.offense(gid)[2], 'closing')
        self.assertGreaterEqual(self.ev(f'{Df}.stats.closeWaits'), 1)   # geste joué, fermeture refusée
        self.h.move_player('A', 100, 100)                                # embrasure libre : fermée
        self.assertTrue(self.until_over(gid))
        self.assertFalse(self.ev('WIN.open'))
        self.assertEqual(self.ev(f'{Df}.stats.windowsClosed'), 1)

    def test_window_left_open_when_its_squares_stay_occupied(self):
        gid = self.mk()
        self.jump_to(11)
        self.run_lua(f'{Df}.CFG.OFFENSE_CLOSE_MS = 6000')
        z = self.thumpers(1)[0]
        self.dpass(3)
        self.assertTrue(self.to_the_kill(gid, z), self.lk()[-15:])
        self.h.move_player('A', 104.5, 110.5)
        self.assertTrue(self.until_over(gid))
        self.assertTrue(self.ev('WIN.open'))
        self.assertEqual(self.ev(f'{Df}.stats.closeGivenUp'), 1)
        self.assertEqual(self.ev(f'{Df}.stats.windowsClosed'), 0)
        self.assertEqual(self.ev('#TOGGLES'), 1)
        self.assertTrue(any('over: window left open' in t for t in self.group_log(gid)), self.group_log(gid))
        self.assertEqual(self.h.errors('solo'), [])

    def test_server_uses_the_window_reported_by_the_owner_never_a_guess(self):
        """LK06-T11 : sur un serveur, un zombie simule par un client n'a jamais de getThumpTarget (ThumpPacket
        seulement relaye) ; fenetre retenue seulement sur rapport du proprietaire, controle par le serveur."""
        gid = self.mk()
        zid = self.horde([(104, 110)])[0]                                # colle a la vitre du foyer
        self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") '
                     'local sq = getCell():getGridSquare(g.home.x, g.home.y, g.home.z) '
                     'local def = sq:getBuildingDef() BID = def and def:getIDString() or nil')
        self.assertIsNotNone(self.ev('BID'))
        S = 'LivingKnox.Senses'
        probe = (f'local z = HARNESS.zombies[{zid}] local t = {Df}.thumpTargetOf(z, BID) '
                 'return rawequal(t, WIN)')
        probe_other = (f'local z = HARNESS.zombies[{zid}] return {Df}.thumpTargetOf(z, "another building") == nil')

        self.n = 0

        def report(w):
            self.h.advance_ms(200)                                       # liste des zombies du serveur relue
            self.n += 1
            args = f'{{ n = {self.n}' + (f', w = {w}' if w else '') + ' }'
            before = self.ev(f'{S}.stats.thumpsDropped or 0')
            kept = self.run_lua(f'return {S}.onThumps(HARNESS.players.A, {args})')
            self.assertIsNotNone(kept)
            return self.ev(f'{S}.stats.thumpsDropped or 0') - before
        good = f'{{ {{ o = {zid}, x = 105, y = 110, z = 0, k = "W" }} }}'
        self.assertIs(self.run_lua(probe), False)                        # solo : getThumpTarget seul
        self.run_lua(f'REAL_IS_SERVER = isServer; isServer = function() return true end '
                     f'HARNESS.zombies[{zid}].getOwner = function() return "client A" end '
                     f'HARNESS.zombies[{zid}].getOwnerPlayer = function() return HARNESS.players.A end')
        try:
            self.assertIs(self.run_lua(probe), False)                    # aucun rapport : aucune deduction
            self.assertEqual(report(good), 0)
            self.assertEqual(self.ev(f'{S}.stats.thumps'), 1)
            self.assertIs(self.run_lua(probe), True)                     # rapport du proprietaire
            self.assertIs(self.run_lua(probe_other), True)               # fenetre d'un autre foyer : non
            # Copie du serveur sans case courante, ou case en retard dans la maison (campagne MP du 2026-10-15) :
            # la case de la position compte.
            for cur in ('nil', 'HARNESS.square(106, 110, 0)'):
                self.run_lua(f'HARNESS.zombies[{zid}].getCurrentSquare = function() return {cur} end')
                self.assertIs(self.run_lua(probe), True)
            self.run_lua(f'HARNESS.zombies[{zid}].getCurrentSquare = nil')
            self.assertGreaterEqual(self.ev(f'{Df}.stats.thumpReported'), 1)
            # Fenetre inexistante a la case ou au bord indiques : entree retiree, rapport precedent remplace.
            for bad in (f'{{ {{ o = {zid}, x = 106, y = 110, z = 0, k = "W" }} }}',
                        f'{{ {{ o = {zid}, x = 105, y = 110, z = 0, k = "N" }} }}',
                        f'{{ {{ o = 9999, x = 105, y = 110, z = 0, k = "W" }} }}'):
                with self.subTest(bad=bad):
                    self.assertEqual(report(bad), 1)
                    self.assertIs(self.run_lua(probe), False)
            # Copie du zombie hors de portee de la fenetre (5,5 cases) : retiree a la reception.
            self.h.move_zombie(zid, 99.5, 110.5)
            self.assertEqual(report(good), 1)
            self.assertIs(self.run_lua(probe), False)
            self.h.move_zombie(zid, 104.5, 110.5)
            self.assertEqual(report(good), 0)
            self.assertIs(self.run_lua(probe), True)
            # Zombie parti apres le rapport : refuse a l'usage aussi.
            self.h.move_zombie(zid, 99.5, 110.5)
            self.assertIs(self.run_lua(probe), False)
            self.h.move_zombie(zid, 104.5, 110.5)
            # Rapport trop vieux (plus de THUMP_MS) : plus cru.
            self.assertIs(self.run_lua(probe), True)
            self.h.advance_ms(int(self.ev(f'{S}.CHECK.THUMP_MS')) + 100)
            self.assertIs(self.run_lua(probe), False)
            # Rapport suivant sans fenetre : la cible disparait.
            self.assertEqual(report(good), 0)
            self.assertIs(self.run_lua(probe), True)
            self.assertEqual(report(None), 0)
            self.assertIs(self.run_lua(probe), False)
            # Client qui ne simule pas ce zombie : entree retiree (seul le proprietaire voit ses coups).
            self.run_lua(f'HARNESS.zombies[{zid}].getOwnerPlayer = function() return HARNESS.players.B end')
            self.assertEqual(report(good), 1)
            self.assertIs(self.run_lua(probe), False)
            # Rapport rejoue (numero deja vu) : refuse en entier.
            self.run_lua(f'HARNESS.zombies[{zid}].getOwnerPlayer = function() return HARNESS.players.A end')
            self.h.advance_ms(200)
            self.assertIsNone(self.run_lua(f'return {S}.onThumps(HARNESS.players.A, {{ n = 1, w = {good} }})'))
            self.assertIs(self.run_lua(probe), False)
            self.assertEqual(self.ev(f'{S}.stats.thumpsDropped'), 5)
            self.assertEqual(self.h.errors('solo'), [])
        finally:
            self.run_lua('isServer = REAL_IS_SERVER')

    def test_malformed_thump_entries_refuse_the_summary(self):
        S = 'LivingKnox.Senses'
        for bad, why in (('{ { o = -1, x = 1, y = 1, z = 0, k = "W" } }', 'out of bounds'),
                         ('{ { o = 1.5, x = 1, y = 1, z = 0, k = "W" } }', 'out of bounds'),
                         ('{ { o = 1, x = 1, y = 1, z = 40, k = "W" } }', 'out of bounds'),
                         ('{ { o = 1, x = 1, y = 1, z = 0, k = "E" } }', 'bad report'),
                         ('{ { o = 1, x = "1", y = 1, z = 0, k = "W" } }', 'bad report'),
                         ('"x"', 'out of bounds'),
                         ('{ ' + ', '.join(f'{{ o = {i}, x = 1, y = 1, z = 0, k = "W" }}' for i in range(5)) + ' }',
                          'out of bounds')):
            with self.subTest(bad=bad):
                self.assertEqual(self.run_lua(f'return ({S}.validateThumps({bad}))'), why)

    def test_more_zombies_waiting_than_members_near_the_window_no_opening(self):
        gid = self.mk()
        self.jump_to(11)
        self.thumpers(3)
        self.dpass(4)
        self.assertEqual(self.plan(gid)[0], 'hold')                      # 3 zombies contre 3 valides : pas débordé
        self.assertIsNone(self.offense(gid))
        self.assertTrue(any(re.search(r'no window offensive: window 105,110,0,W: 3 zombie\(s\) waiting > 1 x [12] '
                                      r'able member\(s\)', line) for line in self.lk()), self.lk()[-10:])
        self.dpass(4, walk=1.0)
        self.assertFalse(self.ev('WIN.open'))
        self.assertEqual(self.ev(f'{Df}.stats.offenses'), 0)

    def test_overwhelmed_group_never_opens(self):
        gid = self.mk()
        self.jump_to(11)
        self.run_lua(f'{Df}.CFG.WITHDRAW_RATIO = 0 {Df}.CFG.HOLD_RATIO = -1')   # 1 zombie > 0 x 3 : repli
        self.thumpers(1)
        self.dpass(5, walk=1.0)
        self.assertEqual(self.plan(gid)[0], 'withdraw')
        self.assertIsNone(self.offense(gid))
        self.assertFalse(self.ev('WIN.open'))
        self.assertEqual(self.ev(f'{Df}.stats.offenses'), 0)

    def test_unfit_member_never_opens(self):
        gid = self.mk()
        self.jump_to(11)
        self.hurt(gid, 'm-1', 0.3)                                       # blessé : à l'abri, jamais ouvreur
        z = self.thumpers(1)[0]
        self.dpass(4, walk=1.0)
        off = self.offense(gid)
        self.assertIsNotNone(off)                                        # un autre membre, valide, ouvre
        self.assertNotEqual(off[1], 'm-1')
        self.assertTrue(self.place_of(gid, 'm-1').startswith('shelter'))
        self.assertIsNotNone(self.h.zombie('solo', z))

    def test_overwhelmed_while_opening_cancels_and_keeps_the_window_closed(self):
        gid = self.mk()
        self.jump_to(11)
        self.thumpers(1)
        self.dpass(3)
        self.assertEqual(self.offense(gid)[2], 'opening')
        self.run_lua(f'{Df}.CFG.WITHDRAW_RATIO = 0 {Df}.CFG.HOLD_RATIO = -1 {Df}.state.groups["{gid}"].at = nil')
        self.dpass(4, walk=1.0)
        self.assertIsNone(self.offense(gid))
        self.assertFalse(self.ev('WIN.open'))
        self.assertTrue(any('over: group overwhelmed, window kept closed' in t for t in self.group_log(gid)))

    def test_barricaded_or_alarmed_or_stuck_window_is_left_alone(self):
        gid = self.mk()
        self.jump_to(11)
        self.run_lua('WIN.planks = 1')
        self.thumpers(1)
        self.dpass(4, walk=1.0)
        self.assertIsNone(self.offense(gid))
        self.run_lua('WIN.planks = 0 WIN.permaLocked = true')
        self.dpass(2, walk=1.0)
        self.assertIsNone(self.offense(gid))
        self.run_lua('WIN.permaLocked = false')
        self.dpass(2, walk=1.0)
        self.assertIsNotNone(self.offense(gid))


class SuiteTests(WindowKillStack):
    def test_suite_is_listed(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKWindowKill.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.windowkill", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.windowkill')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)


class SourceTests(unittest.TestCase):
    def test_sources_are_ascii_and_kahlua_safe(self):
        for path in MOD_FILES + [SUITE_FILE]:
            raw = path.read_text(encoding='utf-8')
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw, flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII code in {path.name}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'\bbit32\b', r'<<|>>'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))
        self.assertTrue(all(b < 128 for b in SUITE_FILE.read_bytes()), 'non ASCII byte in the suite')


if __name__ == '__main__':
    unittest.main(verbosity=1)
