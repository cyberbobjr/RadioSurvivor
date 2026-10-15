"""Tests hors jeu de l'alerte de proximité des PNJ Living Knox (LK05-T08) : server/LivingKnox/LK_Alert.lua (autorité),
branchée dans LK_Decisions.lua (comportement « alert », règle threat), et client/LivingKnox/LK_AlertView.lua (cri
joué par chaque client proche).

    python RadioSurvivor/tests/test_lk_alert.py

Bancs :
- logique pure (menaces d'alerte, une seule fois par menace, niveau qui retombe, écouteurs, attitude « inconnu »,
  cascade) sur le serveur d'un banc tests/harness.py ;
- pile complète (corps, consignes LK03, exécutant, relais, routines) avec le groupe de test « deciders » de
  test_lk_decisions.py dans la maison HOUSE de test_lk_routines.py : solo et serveur dédié + deux clients.
Doublures ajoutées, fidèles aux surcharges Java (base kahlua-lua.md, « Argument nil vers une méthode Java
surchargée ») : émetteur de personnage playSoundImpl(String, IsoObject) seule surcharge à deux arguments
(J/characters/CharacterSoundEmitter.java:190-201), émetteur libre playSoundImpl(String, IsoGridSquare) qui échoue sur
une case nil et playSoundImpl(String, boolean, IsoObject) (J/../fmod/fmod/FMODSoundEmitter.java:431-490), bruit
addSound(source, x, y, z, rayon, volume) à entiers (J/Lua/LuaManager.java:9239-9241). La réplique « alert » passe par
une doublure de LivingKnox.Speech.bark (sa livraison est prouvée par test_lk_speech.py). Les doublures NE PROUVENT PAS
l'API réelle, seulement la logique : alerte une fois par menace, membres réveillés et tâches interrompues, niveau qui
retombe et retour à la routine, mêmes effets chez deux clients, aucune décision côté client.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_routines import RoutineStack  # noqa: E402

A = 'LivingKnox.Alert'
D = 'LivingKnox.Decisions'
ALERT = 'server/LivingKnox/LK_Alert.lua'
VIEW = 'client/LivingKnox/LK_AlertView.lua'
SUITE = 'shared/RST/suites/RST_LKAlert.lua'

# Autorité : bruit du monde enregistré (entiers exigés), réplique « alert » enregistrée, écouteur de test.
AUTHORITY_DOUBLES = r'''
NOISES = {}
local prevAdd = addSound
addSound = function(src, x, y, z, r, v)
    for _, n in ipairs({ x, y, z, r, v }) do
        HARNESS.num(n, 'addSound')
        if n ~= math.floor(n) then error('addSound: int expected, got ' .. tostring(n), 2) end
    end
    NOISES[#NOISES + 1] = { src = src, x = x, y = y, z = z, r = r, v = v }
    if prevAdd ~= nil then return prevAdd(src, x, y, z, r, v) end
end
SENT = {}
if isServer() then
    local prevSend = sendServerCommand
    sendServerCommand = function(player, module, command, args)
        if module == "LivingKnox" and command == "alertCry" then
            SENT[#SENT + 1] = { to = player:getUsername(), id = args.c.id, args = args }
        end
        return prevSend(player, module, command, args)
    end
end
BARKS = {}
LivingKnox.Speech = LivingKnox.Speech or {}
LivingKnox.Speech.bark = function(npc, situation, opts)
    BARKS[#BARKS + 1] = { npc = npc, situation = situation, range = opts and opts.range }
    return { id = "sp-" .. #BARKS, heard = {}, names = {}, line = situation .. "_1" }
end
RAISED, CALMED = {}, {}
function LISTEN()
    LivingKnox.Alert.subscribe("test", {
        raised = function(gid, info, event)
            RAISED[#RAISED + 1] = { gid = gid, id = info.id, kind = info.kind, x = info.x, y = info.y, event = event }
        end,
        calm = function(gid, info) CALMED[#CALMED + 1] = { gid = gid, id = info.id } end })
end
'''

# Clients (et solo) : émetteurs fidèles aux surcharges Java ; voix jouées enregistrées.
CLIENT_DOUBLES = r'''
CRIES = {}
local Z = HARNESS.classes.IsoZombie
local getEm = Z.getEmitter
local function charPlay(self, ...)
    local n = select('#', ...)
    local name, obj = ...
    if n ~= 2 or type(name) ~= 'string' then error('No implementation found for playSoundImpl', 2) end
    if obj ~= nil and type(obj) ~= 'table' then error('playSoundImpl: IsoObject expected', 2) end
    CRIES[#CRIES + 1] = { via = 'body', name = name, o = self.owner and self.owner.onlineID }
    return 7
end
function Z:getEmitter()
    local e
    if getEm ~= nil then
        e = getEm(self)
    else
        e = rawget(self, 'lkEmitter') or setmetatable({ owner = self, playing = {} }, { __index = {} })
        rawset(self, 'lkEmitter', e)
    end
    local mt = getmetatable(e)
    local idx = type(mt.__index) == 'table' and mt.__index or mt
    rawset(idx, 'playSoundImpl', charPlay)
    return e
end
local Free = {}
Free.__index = Free
function Free:playSoundImpl(...)
    local n = select('#', ...)
    local name, a, b = ...
    if type(name) ~= 'string' then error('No implementation found for playSoundImpl', 2) end
    if n == 2 then
        -- Kahlua choisit playSoundImpl(String, IsoGridSquare) pour un nil : NPE (FMODSoundEmitter.java:431-442).
        if a == nil then error('java.lang.NullPointerException: Cannot read field "x" because "square" is null', 2) end
    elseif n ~= 3 or type(a) ~= 'boolean' then
        error('No implementation found for playSoundImpl', 2)
    end
    CRIES[#CRIES + 1] = { via = 'free', name = name, x = self.x, y = self.y, z = self.z }
    return 8
end
local prevWorld = getWorld
getWorld = function()
    local w = prevWorld ~= nil and prevWorld() or {}
    w.getFreeEmitter = function(self, x, y, z)
        for _, v in ipairs({ x, y, z }) do HARNESS.num(v, 'getFreeEmitter') end
        return setmetatable({ x = x, y = y, z = z }, Free)
    end
    return w
end
'''

# Suite lk.alert sur le banc : addZombiesInOutfit (LuaManager.java) crée un zombie ordinaire, vu par chaque membre
# incarné tant qu'il existe (le banc ne simule pas la vue réelle, prouvée par test_lk_senses.py ; solo : onlineId -1).
VANILLA_ZOMBIES = r'''
VANILLA = {}
local nextId = 5000
addZombiesInOutfit = function(x, y, z, n, outfit, female)
    for _, v in ipairs({ x, y, z, n }) do HARNESS.num(v, 'addZombiesInOutfit') end
    nextId = nextId + 1
    local zb = HARNESS.spawnZombie(nextId, x + 0.5, y + 0.5, z, "solo")
    VANILLA[nextId] = true
    return HARNESS.list({ zb })
end
local base = LivingKnox.Senses.perceived
LivingKnox.Senses.perceived = function(id)
    local per = base(id)
    local body = LivingKnox.Groups.findNpc(id) ~= nil and LivingKnox.Bodies.find(id) or nil
    if body == nil then return per end
    local out = { ms = 0, age = 0, stale = false, nz = 0, seen = 0, heard = 0, p = {}, z = {}, n = {} }
    for _, e in ipairs(per and per.p or {}) do out.p[#out.p + 1] = e end
    for _, e in ipairs(per and per.z or {}) do out.z[#out.z + 1] = e end
    local ids = {}
    for zid in pairs(VANILLA) do ids[#ids + 1] = zid end
    table.sort(ids)
    for _, zid in ipairs(ids) do
        local zb = HARNESS.zombies[zid]
        if zb ~= nil then
            local dx, dy = zb:getX() - body:getX(), zb:getY() - body:getY()
            out.z[#out.z + 1] = { o = -1, x = math.floor(zb:getX()), y = math.floor(zb:getY()), z = 0, a = 1, s = true,
                h = false, d = math.sqrt(dx * dx + dy * dy) }
        end
    end
    return out
end
'''

ALERT_VIEW = r'''
function AV(e)
    return { id = e.id or "al-1-1", npc = e.npc or "lk-1", o = e.o or 3, x = e.x or 100, y = e.y or 100, z = e.z or 0,
        s = e.s or "VoiceMaleShoutHey", k = "zombie" }
end
'''


class PureAlertBase(PureBase):
    def setUp(self):
        super().setUp()
        if self.ev(f'{A} == nil'):
            self.run_lua(f'require "LivingKnox/LK_Alert"')
        self.run_lua(AUTHORITY_DOUBLES)
        self.run_lua(r'''
            HOME = { x = 100, y = 100, z = 0 }
            function TH(kind, key, x, y, d, z)
                return { kind = kind, key = key, label = key, x = x, y = y, z = z or 0, d = d, seen = true }
            end
            SPOT = { npc = "lk-1", mid = "m-1", x = 100.5, y = 100.5, z = 0, female = false }
        ''')

    def note(self, kind, key, minute, x=105, y=100, d=5, gid='grp-1'):
        return self.run_lua(f'local ev, a = {A}.note("{gid}", TH("{kind}", "{key}", {x}, {y}, {d}), SPOT, {minute}, '
                            'HOME) return ev, a.id, a.kind, a.key, a.n')


class ThreatTests(PureAlertBase):
    def test_threats_near_the_member_or_the_home_only(self):
        per = ('{ stale = false, z = { { o = 5, x = 106, y = 100, z = 0, s = true, h = false, d = 6 }, '
               '{ o = -1, x = 130, y = 130, z = 0, s = false, h = true, d = 9 }, '
               '{ o = 7, x = 160, y = 100, z = 0, s = true, h = false, d = 40 }, '
               '{ o = 8, x = 112, y = 100, z = 0, s = false, h = false, d = 12 } }, '
               'p = { { u = "H", x = 120, y = 100, z = 0, s = true, h = false, d = 20 }, '
               '{ u = "U", x = 110, y = 100, z = 0, s = true, h = false, d = 10 }, '
               '{ u = "K", x = 101, y = 100, z = 0, s = true, h = false, d = 1 } } }')
        out = self.run_lua(f'local t = {A}.threatsOf({per}, {{ H = "hostile", U = "intruder" }}, HOME) '
                           'local r = {} for i, e in ipairs(t) do r[i] = e.kind .. ":" .. e.key end '
                           'return table.concat(r, " ")')
        # Gravité d'abord ; zombie anonyme (solo) clé commune ; zombie à 40 cases et zombie ni vu ni entendu écartés ;
        # joueur connu (K, absent des genres) écarté ; intrus à 10 cases du foyer gardé (près du foyer).
        self.assertEqual(out, 'hostile:p:H intruder:p:U zombie:z:5 zombie:z?')
        self.assertEqual(self.run_lua(f'return #{A}.threatsOf({{ stale = true, z = {{ {{ o = 1, x = 100, y = 100, '
                                      'z = 0, s = true, d = 1 } } }, {}, HOME)'), 0)
        self.assertEqual(self.run_lua(f'return #{A}.threatsOf(nil, {{}}, HOME)'), 0)
        # Intrus à 13 cases du foyer et 9 du membre : ni près de l'un ni de l'autre ; zombie deux étages plus haut.
        self.assertIs(self.ev(f'{A}.isNear(TH("intruder", "p:X", 113, 100, 9), HOME)'), False)
        self.assertIs(self.ev(f'{A}.isNear(TH("zombie", "z:1", 110, 100, 12, 2), HOME)'), False)
        self.assertIs(self.ev(f'{A}.isNear(TH("zombie", "z:1", 110, 100, 12, 1), HOME)'), True)

    def test_unknown_player_is_an_intruder_known_friend_is_not(self):
        code = r'''
            local pairs_ = {}
            LivingKnox.Hostility = {
                keyOf = function(p) return p.key end,
                isKnown = function(gid, key) return pairs_[key] ~= nil end,
                get = function(gid, key) return { level = pairs_[key] or "cautious", trend = "stable" } end,
                levelOf = function(v) return v end,
                startFor = function(t) return t == "raiders" and "hostile" or "cautious" end,
            }
            pairs_.friend, pairs_.foe, pairs_.wary = "favorable", "hostile", "wary"
            local K = LivingKnox.Alert.playerKind
            return K("grp-1", "settlers", { key = "friend" }), K("grp-1", "settlers", { key = "foe" }),
                K("grp-1", "settlers", { key = "stranger" }), K("grp-1", "settlers", { key = "wary" }),
                K("grp-1", "settlers", {}), K("grp-1", "raiders", { key = "stranger" })
        '''
        self.assertEqual(self.run_lua(code), (None, 'hostile', 'intruder', 'intruder', 'intruder', 'hostile'))


class OncePerThreatTests(PureAlertBase):
    def test_one_alert_per_threat_joined_escalated_and_resumed_without_cry(self):
        self.assertEqual(self.note('zombie', 'z:5', 600), ('raised', 'al-1', 'zombie', 'z:5', 1))
        for minute in (600, 601, 602):                      # même menace revue : aucune nouvelle alerte
            self.assertEqual(self.note('zombie', 'z:5', minute)[0], 'seen')
        self.assertEqual(self.note('zombie', 'z:6', 602)[:2], ('joined', 'al-1'))
        self.assertEqual(self.note('intruder', 'p:U', 603)[:3], ('escalated', 'al-1', 'intruder'))
        self.assertEqual(self.note('zombie', 'z:5', 603)[2], 'intruder')   # la plus grave reste la dernière position
        # Calme : niveau retombé ; la même menace revue dans FORGET_MIN rallume l'alerte sans la redéclencher.
        calm = self.ev(f'{A}.levelAt({A}.state.groups["grp-1"].alert, 603) ')
        self.assertGreater(calm, self.ev(f'{A}.CFG.CALM'))
        self.assertEqual(self.run_lua(f'return {A}.update(640)'), 1)
        self.assertIsNone(self.ev(f'{A}.get("grp-1")'))
        self.assertEqual(self.note('zombie', 'z:5', 650)[:2], ('resumed', 'al-2'))
        self.run_lua(f'{A}.update(700)')
        # Au-delà de FORGET_MIN : menace oubliée, nouvelle alerte déclenchée.
        self.assertEqual(self.note('zombie', 'z:5', 650 + 61)[:2], ('raised', 'al-3'))
        # Deux groupes : mémoires distinctes.
        self.assertEqual(self.note('zombie', 'z:5', 711, gid='grp-2')[0], 'raised')

    def test_level_decays_with_time_and_extra_threats_raise_it(self):
        self.note('zombie', 'z:5', 600)
        lvl = self.ev(f'{A}.CFG.LEVEL.zombie')
        decay = self.ev(f'{A}.CFG.DECAY')
        self.assertEqual(self.ev(f'{A}.get("grp-1", 600).level'), lvl)
        self.assertEqual(self.ev(f'{A}.get("grp-1", 602).level'), lvl - 2 * decay)
        self.note('zombie', 'z:6', 602)                     # nouvelle menace : niveau relevé + EXTRA
        self.assertEqual(self.ev(f'{A}.get("grp-1", 602).level'), lvl + self.ev(f'{A}.CFG.EXTRA'))
        self.assertIs(self.ev(f'{A}.isActive("grp-1", 603)'), True)
        quiet = 602 + (lvl + self.ev(f'{A}.CFG.EXTRA') - self.ev(f'{A}.CFG.CALM')) // decay
        self.assertIs(self.ev(f'{A}.isActive("grp-1", {quiet})'), False)
        self.assertIs(self.ev(f'{A}.isActive("grp-1", {quiet - 1})'), True)

    def test_listeners_called_once_per_raise_and_once_at_calm_errors_isolated(self):
        self.run_lua('LISTEN() LivingKnox.Alert.subscribe("broken", { raised = function() error("boom") end })')
        self.run_lua(f'{A}.subscribe("test", {{ raised = function(g, i, e) RAISED[#RAISED + 1] = {{ id = i.id, '
                     'event = e, x = i.x } end, calm = function(g, i) CALMED[#CALMED + 1] = { id = i.id } end })')
        self.assertEqual(self.ev(f'#{A}.listeners'), 2)       # même nom : remplacé, pas doublé
        for key, minute in (('z:5', 600), ('z:5', 601), ('z:6', 601)):
            ev, a = self.run_lua(f'local ev, a = {A}.note("grp-1", TH("zombie", "{key}", 105, 100, 5), SPOT, '
                                 f'{minute}, HOME) if ev == "raised" or ev == "escalated" then '
                                 f'{A}.onRaised("grp-1", a, ev, {minute}) end return ev, a.id')
        self.assertEqual(len(lua_list(self.ev('RAISED'))), 1)
        self.assertEqual(self.ev('RAISED[1].event'), 'raised')
        self.assertEqual(self.ev(f'{A}.stats.listenerErrors'), 1)
        self.run_lua(f'{A}.update(700) {A}.update(701)')
        self.assertEqual(len(lua_list(self.ev('CALMED'))), 1)
        self.assertTrue(self.run_lua(f'return {A}.unsubscribe("broken")'))


class CascadeAlertTests(PureAlertBase):
    ALERT = ('alert = { id = "al-1", key = "alert:al-1", kind = "zombie", label = "z:5", x = 110, y = 100, z = 0, '
             'd = 9.5, level = 45 }')

    def test_alert_comes_first_and_faces_the_last_known_position(self):
        rule, b, why = self.decide(self.ALERT)
        self.assertEqual((rule, b), ('threat', 'alert'))
        self.assertIn('group alert al-1: zombie z:5 last seen at 110,100,0', why)
        self.assertEqual(self.run_lua(f'return {D}.decide(CTX({{ {self.ALERT} }})).angle'), 0)   # est
        # Endormi la nuit, fatigué : l'alerte le réveille (rang 1 avant la fatigue et le poste).
        self.assertEqual(self.decide(self.ALERT + ', duty = "rest", night = true, needs = { fatigue = 95 }')[:2],
                         ('threat', 'alert'))
        # Sa propre menace perçue passe avant la position partagée.
        self.assertEqual(self.decide(self.ALERT + ', threat = ZOMBIE(3)')[:2], ('threat', 'watch'))   # LK06-T07 : tient
        # Interruption : corvée en cours -> alerte ; alerte gardée jusqu'à l'échéance (même clé).
        st = self.run_lua(f'local a = {D}.decide(CTX({{ duty = "keeper" }})) '
                          f'local b = {D}.decide(CTX({{ {self.ALERT} }})) '
                          f'local c = {D}.decide(CTX({{ {self.ALERT}, minute = 601 }})) '
                          f'local r1, w1 = {D}.replaces(a, b, 600) return r1, w1, {D}.replaces(b, c, 601)')
        self.assertEqual(st, (True, 'interrupted', False))
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.alert.vigil'), 'guard')
        self.assertIs(self.ev(f'{D}.allows(CTX({{ combatant = true }}), "alert")'), True)

    def test_member_out_of_reach_is_not_alerted(self):
        self.note('zombie', 'z:5', 600, x=105, y=100)
        self.assertIsNotNone(self.ev(f'{A}.forMember("grp-1", 120.5, 100.5, 0, false, 601)'))
        self.assertIsNone(self.ev(f'{A}.forMember("grp-1", 150.5, 100.5, 0, false, 601)'))
        self.assertIsNotNone(self.ev(f'{A}.forMember("grp-1", 150.5, 100.5, 0, true, 601)'))   # au foyer
        self.assertIsNone(self.ev(f'{A}.forMember("grp-1", 120.5, 100.5, 0, false, 700)'))     # retombée
        self.assertEqual(self.ev(f'{A}.forMember("grp-1", 100.5, 100.5, 0, false, 601).key'), 'alert:al-1')


class KahluaParityTests(PureAlertBase):
    def test_same_line_as_the_real_vm(self):
        # Programme KR-ALERT de tests/test_kahlua.py : même ligne sous lupa et dans la VM Kahlua du jeu.
        prog = next(p for p in self._programs() if isinstance(p, str) and 'KR-ALERT' in p)
        self.assertEqual(self.run_lua(prog[len('eval:'):]), 'KR-ALERT 2 z? z:5 raised seen joined 45 6 alert:al-1 false')

    @staticmethod
    def _programs():
        import test_kahlua
        for value in vars(test_kahlua).values():
            if isinstance(value, list) and any(isinstance(v, str) and 'KR-ALERT' in v for v in value):
                return value
        raise AssertionError('KR-ALERT program not found in tests/test_kahlua.py')


class AlertStack(RoutineStack):
    """Pile complète, groupe « deciders » (combattant m-1, ouvrier m-2, combattant m-3) dans la maison HOUSE."""

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, AUTHORITY_DOUBLES)
        h.load(srv, 'LISTEN()')
        for m in (['solo'] if self.mode == 'solo' else ['A', 'B']):
            h.load(m, CLIENT_DOUBLES)
            h.load(m, VIEW)
        return h

    def night_with_sleepers(self):
        gid = self.mk()
        self.jump_to(23)
        self.dpass(2)
        sleepers = [m for m in ('m-1', 'm-2', 'm-3') if self.b(gid, m) == 'sleep']
        sentry = [m for m in ('m-1', 'm-2', 'm-3') if m not in sleepers]
        self.assertEqual(len(sleepers), 2)
        if self.mode != 'solo':                       # MP : corps sans marche simulée, en route vers leur lit
            return gid, sentry[0], sleepers
        for _ in range(60):
            self.dpass(1, walk=1.0)
            if all(self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{m}"))') == 'sit' for m in sleepers):
                break
        for m in sleepers:
            self.assertEqual(self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{m}"))'), 'sit', m)
        return gid, sentry[0], sleepers

    def zombie_seen_by(self, gid, mid, o=950, dx=4):
        x, y = self.body_xy(gid, mid)
        self.run_lua(f'SEE_ZOMBIE(MEMBER_NPC("{gid}", "{mid}"), {int(x) + dx}, {int(y)}, {dx}, {o})')
        return int(x) + dx, int(y)

    def gesture(self, gid, mid, m=None):
        return self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{mid}"))', m)


class SoloAlertTests(AlertStack):
    mode = 'solo'

    def test_alert_once_sleepers_woken_and_back_to_routine(self):
        gid, sentry, sleepers = self.night_with_sleepers()
        zx, zy = self.zombie_seen_by(gid, sentry)
        self.dpass(3)
        # Alerte déclenchée une fois : cri (réplique, bruit, voix), journal du groupe, écouteur « portes ».
        self.assertEqual(self.ev(f'{A}.stats.raised'), 1)
        self.assertEqual(self.ev('#BARKS'), 1)
        self.assertEqual(self.ev('BARKS[1].situation'), 'alert')
        self.assertEqual(self.ev('BARKS[1].npc'), self.npc_of(gid, sentry))
        noises = lua_list(self.ev('NOISES'))
        alert_noises = [n for n in noises if n.r == self.ev(f'{A}.CFG.SHOUT.zombie') and n.src is None]
        self.assertEqual(len(alert_noises), 1)
        self.assertEqual(self.ev('#CRIES'), 1)
        self.assertIn(self.ev('CRIES[1].name'), ('VoiceMaleShoutHey', 'VoiceFemaleShoutHey'))
        self.assertEqual(self.ev('#RAISED'), 1)
        self.assertEqual((self.ev('RAISED[1].x'), self.ev('RAISED[1].y')), (zx, zy))
        log = lua_list(self.run_lua(f'local out = {{}} for _, e in ipairs(LivingKnox.Groups.get("{gid}").log) do '
                                    'if e.kind == "alert" then out[#out + 1] = e.text end end return out'))
        self.assertEqual(len(log), 1)
        self.assertEqual(len(self.lines(' raised by ')), 1)
        # Dormeurs réveillés : debout, vigilance de garde, regard vers la dernière position connue ; geste d'alerte.
        for m in sleepers:
            npc = self.npc_of(gid, m)
            self.assertEqual(self.b(gid, m), 'alert', m)
            self.assertNotEqual(self.gesture(gid, m), 'sit', m)
            self.assertIn(self.gesture(gid, m), ('guard', 'crouch'), m)
            self.assertEqual(self.ev(f'LivingKnox.Senses.vigilanceOf("{npc}")'), 'guard', m)
            self.assertIsNone(self.ev(f'LivingKnox.Routines.get("{npc}")'), m)
        self.assertEqual(self.ev(f'{A}.stats.woken'), 2)
        self.assertEqual(self.gesture(gid, 'm-2'), 'guard')                  # LK06-T07 : ouvrier valide, en garde
        # Menace toujours vue : aucun nouveau cri.
        self.dpass(6)
        self.assertEqual((self.ev(f'{A}.stats.raised'), self.ev('#BARKS'), self.ev('#CRIES'), self.ev('#RAISED')),
                         (1, 1, 1, 1))
        # Menace partie : le niveau retombe avec le temps, alerte close une fois, retour au sommeil.
        self.run_lua('PERCEPTION = {}')
        self.h.advance(2)
        self.dpass(2)
        self.assertIs(self.ev(f'{A}.isActive("{gid}", {D}.currentMinute())'), True)
        for m in sleepers:
            self.assertEqual(self.b(gid, m), 'alert', m)
        self.h.advance(10)
        self.dpass(3)
        self.assertIsNone(self.ev(f'{A}.get("{gid}")'))
        self.assertEqual(self.ev('#CALMED'), 1)
        for m in sleepers:
            self.assertEqual(self.b(gid, m), 'sleep', m)
        for _ in range(30):
            self.dpass(1, walk=1.0)
            if all(self.gesture(gid, m) == 'sit' for m in sleepers):
                break
        for m in sleepers:
            self.assertEqual(self.gesture(gid, m), 'sit', m)
        # Même zombie revu dans l'heure : alerte rallumée sans cri ; un autre zombie, plus tard, en déclenche une.
        self.zombie_seen_by(gid, sentry)
        self.dpass(3)
        self.assertEqual((self.ev(f'{A}.stats.raised'), self.ev('#CRIES')), (1, 1))
        self.assertEqual(self.ev(f'{A}.stats.resumed'), 1)
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)
        self.dpass(2)
        self.zombie_seen_by(gid, sentry, o=951)
        self.dpass(3)
        self.assertEqual((self.ev(f'{A}.stats.raised'), self.ev('#CRIES')), (2, 2))
        self.assertEqual(self.h.errors('solo'), [])

    def test_day_chore_interrupted_by_the_alert_then_resumed(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(3)
        worker = 'm-2'
        for _ in range(40):
            self.dpass(1, walk=1.0)
            if self.b(gid, worker) == 'chore':
                break
        self.assertEqual(self.b(gid, worker), 'chore')
        other = 'm-3' if self.b(gid, 'm-3') != 'guard' else 'm-1'
        self.zombie_seen_by(gid, other)                                       # vu par un AUTRE membre
        self.dpass(3)
        self.assertEqual(self.b(gid, worker), 'alert')                       # corvée interrompue
        npc = self.npc_of(gid, worker)
        self.assertIsNone(self.ev(f'LivingKnox.Routines.get("{npc}")'))
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)
        self.dpass(3)
        self.assertEqual(self.b(gid, worker), 'chore')
        self.assertNotIn(self.gesture(gid, worker), ('guard', 'crouch'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_unknown_player_near_home_is_an_intruder_known_friend_is_not(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        x, y = self.body_xy(gid, 'm-1')
        see = (f'PERCEPTION[MEMBER_NPC("{gid}", "m-1")] = {{ ms = 0, age = 0, stale = false, nz = 0, seen = 1, '
               f'heard = 0, z = {{}}, n = {{}}, p = {{ {{ u = "A", x = {int(x) + 3}, y = {int(y)}, z = 0, s = true, '
               'h = false, d = 3 } } }')
        self.run_lua('LivingKnox.Hostility.keyOf = function(p) return "char-A" end '
                     'LivingKnox.Hostility.isKnown = function(gid, key) return KNOWN_A == true end '
                     'LivingKnox.Hostility.get = function(gid, key) return { level = "favorable", trend = "up" } end')
        self.run_lua('KNOWN_A = true ' + see)
        self.dpass(3)
        self.assertEqual(self.ev(f'{A}.stats.raised'), 0)                     # connu et favorable : rien
        self.run_lua('KNOWN_A = false ' + see)
        self.dpass(3)
        self.assertEqual(self.ev(f'{A}.stats.raised'), 1)                     # inconnu : intrus
        self.assertEqual(self.ev(f'{A}.get("{gid}").kind'), 'intruder')
        self.assertEqual(self.ev('NOISES[#NOISES].r'), self.ev(f'{A}.CFG.SHOUT.intruder'))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerAlertTests(AlertStack):
    """Serveur dédié + deux clients proches : alerte décidée par le serveur seul, même cri et mêmes gestes chez A et B."""

    def observed(self, gid):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        for c in ('A', 'B'):
            rows = []
            for m in ('m-1', 'm-2', 'm-3'):
                npc = self.npc_of(gid, m)
                rows.append(self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                           'local d = e and (e.op .. ":" .. tostring(e.a) .. ":" .. tostring(e.v)) '
                                           f'or "none" return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") .. "|" '
                                           f'.. LivingKnox.Senses.vigilanceOf("{npc}") end)()'))
            out[c] = rows
        return out

    def test_zombie_fought_before_any_report_raises_the_alert(self):
        """Campagne MP 2026-10-14 : le membre tuait un zombie a 3 cases (cible du serveur, Zombies.targetFor) avant que
        le rapport du proprietaire ne le montre ; l'alerte du groupe n'etait jamais levee. Decisions.withTarget ajoute
        cette cible a la perception lue par l'alerte, sur un serveur seulement."""
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        x, y = self.body_xy(gid, 'm-2')
        self.h.spawn_zombie(951, int(x) + 2, int(y))
        D = 'LivingKnox.Decisions'
        self.run_lua('TG = { kind = "zombie", u = "z:951", d = 2, zombie = HARNESS.zombies[951] }')
        self.assertEqual(self.ev(f'#{D}.withTarget(nil, TG).z'), 1)
        self.assertEqual(self.ev(f'{D}.withTarget(nil, TG).z[1].o'), 951)
        self.run_lua('PER = { ms = 0, age = 0, stale = false, nz = 1, p = {}, n = {}, '
                     'z = { { o = 951, x = 1, y = 1, z = 0, a = 1, s = true, h = false, d = 2 } } }')
        self.assertIs(self.ev(f'rawequal({D}.withTarget(PER, TG), PER)'), True)       # deja percu : inchange
        self.assertIs(self.ev(f'rawequal({D}.withTarget(PER, nil), PER)'), True)
        before = self.ev(f'{A}.stats.raised')
        self.run_lua(f'local g = LivingKnox.Groups.get("{gid}") local m = g.members["m-2"] '
                     f'local body = LivingKnox.Bodies.find(m.npc) '
                     f'{A}.observe("{gid}", g, "m-2", m, body, {D}.withTarget(nil, TG), {{}}, '
                     f'{D}.currentMinute())')
        self.assertEqual(self.ev(f'{A}.stats.raised'), before + 1)
        self.assertEqual(self.ev(f'{A}.get("{gid}").label'), 'z:951')

    def test_two_clients_hear_the_same_cry_once_and_see_the_same_alert(self):
        gid, sentry, sleepers = self.night_with_sleepers()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, A))                              # aucune décision côté client
        self.zombie_seen_by(gid, sentry)
        self.dpass(3)
        sent = lua_list(self.ev('SENT'))
        self.assertEqual(sorted(e.to for e in sent), ['A', 'B'])             # une commande par client proche
        ids = {e.id for e in sent}
        self.assertEqual(len(ids), 1)
        self.h.pump()
        self.run_lua('local again = {} for i, e in ipairs(SENT) do again[i] = e end '
                     'for _, e in ipairs(again) do sendServerCommand(HARNESS.players[e.to], "LivingKnox", '
                     '"alertCry", e.args) end')                              # livraison répétée : ignorée
        self.h.pump()
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, '#CRIES'), 1, c)
            self.assertEqual(self.h.eval(c, 'LivingKnox.AlertView.stats.duplicate'), 1, c)
            self.assertEqual(self.h.eval(c, 'LivingKnox.AlertView.last.id'), ids.pop() if c == 'A' else
                             self.h.eval('A', 'LivingKnox.AlertView.last.id'))
        self.assertEqual(self.ev(f'{A}.stats.raised'), 1)
        seen = self.observed(gid)
        self.assertEqual(seen['A'], seen['B'])
        for m in sleepers:
            row = seen['A'][int(m[2:]) - 1]
            self.assertTrue(row.endswith('|guard'), row)                      # vigilance portée par la consigne
            self.assertTrue(row.split('|')[1] in ('guard', 'crouch'), row)    # geste d'alerte relayé
        # Retour à la routine : mêmes consignes, gestes et vigilance chez A et B.
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)
        self.dpass(3)
        back = self.observed(gid)
        self.assertEqual(back['A'], back['B'])
        for m in sleepers:
            self.assertEqual(self.b(gid, m), 'sleep', m)
            self.assertTrue(back['A'][int(m[2:]) - 1].endswith('|sleep'), back['A'])
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class ViewTests(unittest.TestCase):
    """Client seul : voix jouée sur le corps connu ou sur un émetteur libre (surcharge sans nil ambigu)."""

    def setUp(self):
        from harness import Harness
        from test_lk_simulation import SHARED, WORLD
        self.h = Harness(mode='solo', lua_roots=[DEV_LUA])
        self.h.load('solo', WORLD)
        for path in SHARED:
            self.h.load('solo', path)
        self.h.load('solo', CLIENT_DOUBLES)
        self.h.load('solo', VIEW)
        self.h.load('solo', ALERT_VIEW)

    def tearDown(self):
        self.h.close()

    def test_free_emitter_three_args_and_duplicates_and_bad_entries(self):
        self.assertIs(self.h.eval('solo', 'LivingKnox.AlertView.receive(AV({}))'), True)
        self.assertEqual(self.h.eval('solo', 'CRIES[1].via'), 'free')
        self.assertIs(self.h.eval('solo', 'LivingKnox.AlertView.receive(AV({}))'), False)       # doublon
        self.assertIs(self.h.eval('solo', 'LivingKnox.AlertView.receive(AV({ id = "x", s = "Boom" }))'), False)
        self.assertIs(self.h.eval('solo', 'LivingKnox.AlertView.receive({ id = "y" })'), False)
        self.assertEqual(self.h.eval('solo', '#CRIES'), 1)
        self.assertEqual(self.h.eval('solo', 'LivingKnox.AlertView.stats.played'), 1)
        # La doublure refuse la forme fautive (nil en second argument : surcharge IsoGridSquare, NPE en jeu).
        err = self.h.eval('solo', '(function() local ok, e = pcall(function() '
                                  'return getWorld():getFreeEmitter(1, 1, 0):playSoundImpl("VoiceMaleShoutHey", nil) end) '
                                  'return tostring(e) end)()')
        self.assertIn('square', err)

    def test_silent_free_emitter_still_counts_the_voice_launched(self):
        # Son coupé (-nosound) : getFreeEmitter rend un DummySoundEmitter dont playSoundImpl rend 0
        # (J/audio/DummySoundEmitter.java:133-145) ; la voix est lancée quand même (MP du 2026-10-15).
        self.h.load('solo', 'local F = getmetatable(getWorld():getFreeEmitter(0, 0, 0)).__index '
                            'local prev = F.playSoundImpl '
                            'F.playSoundImpl = function(self, ...) prev(self, ...) return 0 end')
        self.assertIs(self.h.eval('solo', 'LivingKnox.AlertView.receive(AV({}))'), True)
        self.assertEqual(self.h.eval('solo', 'LivingKnox.AlertView.stats.played'), 1)
        self.assertEqual(self.h.eval('solo', 'LivingKnox.AlertView.stats.silent'), 1)
        self.assertEqual(self.h.eval('solo', 'LivingKnox.AlertView.last.handle'), 0)


class SourceTests(unittest.TestCase):
    def test_sources_are_kahlua_safe_and_messages_english(self):
        for path in (LUA / 'server' / 'LivingKnox' / 'LK_Alert.lua', LUA / 'client' / 'LivingKnox' / 'LK_AlertView.lua'):
            raw = path.read_text(encoding='utf-8')
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw, flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in the code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'\bbit32\b', r'<<|>>',
                            r'//'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))
            for fmt in re.findall(r'log\(\)\.\w+\("([^"]*)"', code):              # journal en anglais
                self.assertTrue(all(ord(ch) < 128 for ch in fmt), fmt)

    def test_suite_lk_alert_is_ascii(self):
        raw = (DEV_LUA / SUITE).read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')


class SuiteTests(AlertStack):
    mode = 'solo'

    def test_suite_lk_alert_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', VANILLA_ZOMBIES)
        # LK05-T14 : option ZombieAlertDistance (défaut de sandbox-options.txt) lue par le second test de la suite.
        self.h.load('solo', 'getSandboxOptions = function() return { getOptionByName = function(_, n) '
                            'if n == "LivingKnox.ZombieAlertDistance" then return { getValue = function() return 10 end }'
                            ' end return nil end } end')
        self.h.move_player('A', 110, 110)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.alert", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.alert')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.alert", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(6000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 20 == 19:
                self.h.advance(1)                                              # temps de jeu : l'alerte retombe
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 2, results)
        self.assertEqual([r[1] for r in results], ['PASS', 'PASS'], results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKA' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKA] measure alert raised', '[LKA] measure cry', '[LKA] measure members alerted',
                     '[LKA] measure calm', '[LKA] measure thresholds: zombie alert 10',
                     '[LKA] measure crowd: 20 s with 50 zombies 12 to 26 squares away: alerts raised 0'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])


# ------------------------------------------------------------------ portes refermées à l'alerte (complément LK05-T08)

def _obstacles():
    """Banc des portes de test_lk_obstacles.py (import tardif : ses doublures complètent celles des consignes)."""
    import test_lk_obstacles as tob
    return tob


class AlertDoorBase(_obstacles().ObstacleBase):
    """Écouteur "doors" de LK_Obstacles branché sur LivingKnox.Alert : à une alerte déclenchée ou aggravée, portes
    extérieures ouvertes du foyer fermées (verrouillées avec un porteur de la clé au foyer), mêmes contrôles que la
    fermeture à l'arrivée (shutHome)."""

    def make(self, root=None):
        h = super().make(root)
        h.load('solo' if self.mode == 'solo' else 'server', ALERT)
        return h

    def home_with_open_doors(self, member=True):
        """Maison HOUSE de test_lk_obstacles, porte extérieure ouverte (106,102 W) et porte intérieure ouverte ; aucune
        fermeture à l'arrivée (SHUT_DELAY_MS repoussé). Rend le groupe."""
        self.building()
        self.door(open=True)
        self.door(x=108, y=102, kind='W', open=True)
        if self.mode == 'solo':
            self.start()
        else:
            self.npc()
        self.run_lua('LivingKnox.Obstacles.SHUT_DELAY_MS = 3600000')
        gid = self.group(member=member)
        self.passes(2)
        return gid

    def passes(self, n=1):
        self.h.tick(n * self.o('PASS_EVERY') + 1)

    def raise_alert(self, gid, key='z:5', kind='zombie', minute=600):
        return self.run_lua(
            f'local A = LivingKnox.Alert local ev, a = A.note("{gid}", {{ kind = "{kind}", key = "{key}", '
            f'label = "{key}", x = 110, y = 100, z = 0, d = 6, seen = true }}, {{ npc = "lk-1", mid = "m-1", '
            f'x = 102.5, y = 102.5, z = 0, female = false }}, {minute}, {{ x = 108, y = 101, z = 0 }}) '
            f'if ev == "raised" or ev == "escalated" then A.onRaised("{gid}", a, ev, {minute}) end return ev, a.id')

    def interior(self, m=None):
        return self.h.eval(m or ('solo' if self.mode == 'solo' else 'server'), 'DOOR_STATE("108,102,0,W")')


class AlertDoorTests(AlertDoorBase):
    mode = 'solo'

    def test_listener_closes_and_locks_open_exterior_doors_interior_left(self):
        gid = self.home_with_open_doors()
        self.assertIs(self.ev('LivingKnox.Obstacles.state.alertHook == LivingKnox.Alert'), True)
        n = self.ev('#LivingKnox.Alert.listeners')
        names = [self.ev(f'LivingKnox.Alert.listeners[{i}].name') for i in range(1, n + 1)]
        self.assertEqual(names.count('doors'), 1)
        self.assertEqual(self.state('solo'), 'true false false')          # rien avant l'alerte
        ev, aid = self.raise_alert(gid)
        self.assertEqual(ev, 'raised')
        self.assertEqual(self.state('solo'), 'true false false')          # l'écouteur ne touche aucune porte
        self.passes()
        self.assertEqual(self.state('solo'), 'false true true')           # fermée et verrouillée (porteur au foyer)
        self.assertEqual(self.interior(), 'true false false')             # porte intérieure laissée
        self.assertEqual(self.counters('solo'), (1, 0))                   # une bascule, jamais ToggleDoor
        self.assertEqual(self.o('stats.alertShuts'), 1)
        logs = self.lk()
        self.assertTrue(any(f'alert {aid} raised: open exterior doors of its home to be closed' in s for s in logs),
                        logs)
        self.assertTrue(any(f'closed and locked (alert {aid} raised)' in s for s in logs), logs)
        self.assertEqual(self.ev('LivingKnox.Alert.stats.listenerErrors'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_escalation_closes_again_a_door_reopened_after_the_first_alert(self):
        gid = self.home_with_open_doors()
        self.raise_alert(gid)
        self.passes()
        self.assertEqual(self.state('solo'), 'false true true')
        self.run_lua(f'local d = DOORS["{_obstacles().DOOR_KEY}"] d.open, d.locked, d.lockedByKey = true, false, false')
        self.passes(3)
        self.assertEqual(self.state('solo'), 'true false false')          # rouverte : aucune bataille
        self.assertEqual(self.raise_alert(gid, key='z:5', minute=601)[0], 'seen')   # même menace : rien
        self.passes()
        self.assertEqual(self.state('solo'), 'true false false')
        self.assertEqual(self.raise_alert(gid, key='p:H', kind='hostile', minute=602)[0], 'escalated')
        self.passes()
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.o('stats.alertShuts'), 2)

    def test_occupied_door_retried_and_no_key_holder_closes_without_locking(self):
        gid = self.home_with_open_doors(member=False)                     # aucun membre : personne n'a la clé
        self.h.move_player('A', 105.5, 102.5, 0)                          # joueur dans l'encadrement
        self.raise_alert(gid)
        self.passes(2)
        self.assertEqual(self.state('solo'), 'true false false')
        self.assertGreaterEqual(self.o('stats.shutBusy'), 1)
        self.h.move_player('A', 96, 108, 0)
        self.h.tick(self.o('SHUT_RETRY_MS') // self.h.tick_ms + 2 * self.o('PASS_EVERY') + 1)
        self.assertEqual(self.state('solo'), 'false false false')         # fermée, pas verrouillée
        self.assertTrue(any('left unlocked: no member with the key at home (alert' in s for s in self.lk()), self.lk())

    def test_door_on_the_path_of_a_member_is_left_until_it_passed(self):
        gid = self.home_with_open_doors()
        zid = self.ev('LivingKnox.Bodies.find("lk-1"):getOnlineID()')
        self.move()
        self.walk_d(zid, 400, until=lambda: self.h.zombie('solo', zid).x >= 104.6)
        self.raise_alert(gid)
        self.walk_d(zid, self.o('PASS_EVERY') + 1)
        self.assertEqual(self.state('solo'), 'true false false')          # sur son trajet : laissée
        self.walk_d(zid, 1200, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.h.tick(self.o('SHUT_RETRY_MS') // self.h.tick_ms + 2 * self.o('PASS_EVERY') + 1)
        self.assertEqual(self.state('solo'), 'false true true')

    def test_group_without_building_home_or_other_group_changes_nothing(self):
        self.home_with_open_doors()
        other = self.run_lua('local g = LivingKnox.Groups.create({ type = "settlers", name = "Field", '
                             'home = { x = 300, y = 300, z = 0 } }) return g.id')
        self.assertEqual(self.ev(f'LivingKnox.Obstacles.onAlert("{other}", {{ id = "al-x" }}, "raised")'), 0)
        self.passes()
        self.assertEqual(self.state('solo'), 'true false false')
        self.assertIsNone(self.o('stats.alertShuts'))


class MultiplayerAlertDoorTests(AlertDoorBase):
    def test_server_closes_on_alert_and_both_clients_see_it(self):
        gid = self.home_with_open_doors()
        self.raise_alert(gid)
        self.passes()
        self.relay_doors()
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.state(m), 'false true true', m)
        self.assertEqual(self.counters('server'), (1, 0))
        for c in ('A', 'B'):
            self.assertEqual(self.counters(c), (0, 0))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Alert'))
        self.assertEqual(self.h.errors('server'), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
