"""Tests hors jeu des avertissements et sommations des PNJ Living Knox (LK11-T02) : server/LivingKnox/LK_Encounters.lua
(autorité), branché dans LK_Decisions.lua (comportement « warn », règle threat après la retraite et avant la défense),
avec LK_Hostility.lua (action "warn" de chooseTarget, provocation), LK_Combat.lua (coup de semonce par shotEffects,
engagement), LK_Ammo.lua (cartouche retirée) et LK_Speech.lua (répliques traduites IGUI_LK_Warn_*, EN et FR).

    python RadioSurvivor/tests/test_lk_encounters.py

Bancs :
- logique pure (séquence graduée, délai de tolérance, distance de sécurité, repli et reprise, coup de semonce permis,
  zones, répliques, place de « warn » dans la cascade) sur le serveur d'un banc tests/harness.py ;
- pile complète (corps, consignes LK03, exécutant, relais, alerte, combat, munitions, défense) avec le groupe de test
  « deciders » (neutre : ne tire jamais le premier) et un type « fierce » qui tire le premier, dans la maison HOUSE de
  test_lk_routines.py : solo et serveur dédié + deux clients ;
- suite en jeu lk.warn : liste et sources.
La parole passe par une doublure de LivingKnox.Speech.say (auditeurs : joueurs vivants à 0,6 x portée, comme la
lecture complète de la bulle vanilla ; la règle réelle et la livraison sont prouvées par test_lk_speech.py) ; la vue
des joueurs par la perception injectée (PERCEPTION, test_lk_decisions.py). Les doublures NE PROUVENT PAS l'API réelle,
seulement la logique : séquence graduée, jamais de tir sans les deux sommations entendues, jamais de tir d'un groupe
neutre, engagement seulement sur provocation, repli et reprise, même séquence pour deux observateurs.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_defense import DefenseStack  # noqa: E402

ENC = 'server/LivingKnox/LK_Encounters.lua'
SUITE = 'shared/RST/suites/RST_LKWarn.lua'
SUITE_FILE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKWarn.lua'
TRANSLATE = LUA / 'shared' / 'Translate'
E = 'LivingKnox.Encounters'
D = 'LivingKnox.Decisions'
C = 'LivingKnox.Combat'
FIGHTER = 'role = "fighter", allowed = { fight = true, guard = true, defend = true }, combatant = true'

PURE = r'''
function ENC() return LivingKnox.Encounters.new("grp-1", "A") end
function STEP(e, t, inZone, inSafe, d, level)
    return LivingKnox.Encounters.advance(e, { t = t, inZone = inZone, inSafe = inSafe, d = d or 20,
        level = level or "wary" })
end
function HEAR(e) e.heard = e.stage e.told[e.stage] = true e.pending = nil end
'''

# Autorité : parole enregistrée (essais compris) ; auditeurs = joueurs vivants à 0,6 x portée du corps ; DEAF : personne.
# Serveur MP : une commande "speech" par auditeur, comme LK_Speech.deliver. Vue des joueurs : SEE_PLAYERS(gid).
STACK = r'''
SAID, DEAF = {}, false
LivingKnox.Speech = LivingKnox.Speech or {}
LivingKnox.Speech.bandOf = LivingKnox.Speech.bandOf or function(level)
    return (level == "wary" or level == "hostile") and "hostile" or "neutral"
end
LivingKnox.Speech.say = function(npc, what, opts)
    local z = LivingKnox.Bodies.find(npc)
    if z == nil then return nil, "npc not embodied" end
    if type(what) ~= "table" or type(what.key) ~= "string" then error("say: key expected", 2) end
    local heard, names = {}, {}
    for _, p in ipairs(LivingKnox.Bodies.livingPlayers()) do
        local dx, dy = p:getX() - z:getX(), p:getY() - z:getY()
        if not DEAF and math.sqrt(dx * dx + dy * dy) < (opts.range or 25) * 0.6 then
            heard[#heard + 1] = p
            names[#names + 1] = p:getUsername()
        end
    end
    local id = "sp-" .. (#SAID + 1)
    SAID[#SAID + 1] = { npc = npc, key = what.key, band = opts.band, names = table.concat(names, ","), id = id }
    if #heard == 0 then return nil, "nobody hears" end
    if isServer() then
        for _, p in ipairs(heard) do
            sendServerCommand(p, "LivingKnox", "speech", { u = { id = id, k = what.key, npc = npc } })
        end
    end
    return { id = id, heard = heard, names = names }
end
LivingKnox.Hostility.keyOf = function(p) return "char-" .. p:getUsername() end
SEE = {}
function SEE_PLAYERS(gid)
    local g = LivingKnox.Groups.get(gid)
    for _, m in pairs(g.members) do
        local z = m.npc and LivingKnox.Bodies.find(m.npc) or nil
        if z ~= nil then
            local per = { ms = 0, age = 0, stale = false, nz = 0, seen = 0, heard = 0, p = {}, z = {}, n = {} }
            for _, p in ipairs(LivingKnox.Bodies.livingPlayers()) do
                local name = p:getUsername()
                local dx, dy = p:getX() - z:getX(), p:getY() - z:getY()
                local d = math.sqrt(dx * dx + dy * dy)
                if SEE[name] and d <= 40 then
                    per.p[#per.p + 1] = { u = name, x = math.floor(p:getX()), y = math.floor(p:getY()), z = 0, a = 1,
                        s = true, h = false, d = math.floor(d * 10 + 0.5) / 10 }
                end
            end
            PERCEPTION[m.npc] = per
        end
    end
end
function KEYS()
    local out = {}
    for _, s in ipairs(SAID) do out[#out + 1] = string.gsub(s.key, "IGUI_LK_Warn_", "") end
    return table.concat(out, " ")
end
if not LivingKnox.GroupTypes.isKnown("fierce") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "fierce", nameKey = "IGUI_LK_GroupType_raiders", size = { min = 1, max = 12 },
        hostility = 90, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "guard", "defend", "fight" } },
                  worker = { weight = 1, behaviours = { "chores", "cook" } } },
        profiles = {
            { id = "gunner", role = "fighter", weight = 1, weapons = { "Base.Shotgun" }, looks = { "manFairBeard" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
        },
    }))
end
'''

CLIENT = r'''
HEARD = {}
LivingKnox.subscribe("OnServerCommand", "test.heard", function(module, command, args)
    if module == "LivingKnox" and command == "speech" then HEARD[#HEARD + 1] = args.u.id .. ":" .. args.u.k end
end)
function HEARD_LIST() return table.concat(HEARD, " ") end
'''


def translations(lang):
    return json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))


class PureEncounterBase(PureBase):
    def setUp(self):
        super().setUp()
        self.h.load(self.srv, ENC)
        self.run_lua(PURE)


class SequenceTests(PureEncounterBase):
    def test_graduated_sequence_tolerance_and_safety_distance(self):
        code = r'''
            local e = ENC()
            local out = {}
            local function s(...) out[#out + 1] = tostring(STEP(e, ...)) .. "/" .. e.stage .. "/" .. tostring(e.pending) end
            s(0, false, false)                 -- hors zone : rien
            s(1000, true, false, 12)           -- approche : sommation
            s(20000, true, false, 12)          -- sommation pas encore entendue : on ne monte pas
            HEAR(e)
            s(10999, true, false, 12)          -- tolérance (méfiant : 10 s depuis l'étape)
            s(11000, true, false, 12)          -- dernière sommation
            HEAR(e)
            s(12000, true, true, 4)            -- distance de sécurité franchie : au moins MIN_STEP_MS
            s(13500, true, true, 4)            -- étape finale
            HEAR(e)
            s(60000, true, true, 4)            -- étape finale : plus rien
            return table.concat(out, " ")
        '''
        self.assertEqual(self.run_lua(code), 'nil/0/nil start/1/stage nil/1/stage nil/1/nil advance/2/stage '
                                             'nil/2/nil advance/3/stage nil/3/nil')
        # Hostile : tolérance plus courte (6 s).
        code = r'''
            local e = ENC()
            STEP(e, 0, true, false, 12, "hostile") HEAR(e)
            return tostring(STEP(e, 5999, true, false, 12, "hostile")), tostring(STEP(e, 6000, true, false, 12, "hostile"))
        '''
        self.assertEqual(self.run_lua(code), ('nil', 'advance'))

    def test_backing_off_eases_leaving_stands_down_coming_back_resumes(self):
        code = r'''
            local e = ENC()
            local out = {}
            local function s(...) out[#out + 1] = tostring(STEP(e, ...)) .. "/" .. e.stage .. "/" .. tostring(e.pending) end
            STEP(e, 0, true, true, 4) HEAR(e) STEP(e, 2500, true, true, 4) HEAR(e) STEP(e, 5000, true, true, 3) HEAR(e)
            s(6000, true, true, 4)             -- recul d'une case : rien
            s(7000, true, false, 5)            -- recul de deux cases depuis la plus courte (3) : arme abaissée
            s(16999, true, false, 5)
            s(17000, true, false, 5)           -- revient pas, reste : nouvelle escalade après la tolérance
            HEAR(e)
            s(18000, false, false)             -- sorti de la zone : fin de la sommation
            s(30000, false, false)
            s(40000, true, false, 12)          -- revenu dans les RESUME_MS : reprise à l'étape atteinte
            return table.concat(out, " "), e.peak, e.told[1], e.told[2]
        '''
        self.assertEqual(self.run_lua(code), ('nil/3/nil ease/2/nil nil/2/nil advance/3/stage standdown/0/nil nil/0/nil '
                                              'resume/3/again', 3, True, True))
        # Parti plus de RESUME_MS : oubli ; revenu ensuite : nouvelle sommation depuis le début.
        code = r'''
            local e = ENC()
            STEP(e, 0, true, true, 4) HEAR(e) STEP(e, 2500, true, true, 4) HEAR(e)
            local a = STEP(e, 3000, false, false)
            local b = STEP(e, 3000 + 120001, false, false)
            local f = ENC() f.peak, f.out, f.told = 2, 0, { true, true }
            local c = STEP(f, 120001, true, false, 12)
            return a, b, c, f.stage, f.peak, f.told[2] == nil
        '''
        self.assertEqual(self.run_lua(code), ('standdown', 'forget', 'start', 1, 1, True))

    def test_warning_shot_needs_first_strike_loaded_gun_and_both_warnings_heard(self):
        code = r'''
            local M = LivingKnox.Encounters.mayShoot
            local e = ENC() e.stage = 3 e.told = { true, true }
            local f = ENC() f.stage = 3 f.told = { true }
            local g = ENC() g.stage = 2 g.told = { true, true }
            local h = ENC() h.stage = 3 h.told = { true, true } h.shot = true
            return M(e, true, true), M(e, false, true), M(e, true, false), M(f, true, true), M(g, true, true),
                M(h, true, true)
        '''
        self.assertEqual(self.run_lua(code), (True, False, False, False, False, False))

    def test_zones_of_the_home_and_of_the_warner(self):
        Z = f'(function(...) local a, b = {E}.zones(...) return tostring(a) .. "," .. tostring(b) end)'
        home = '{ x = 100, y = 100, z = 0 }'
        self.assertEqual(self.ev(f'{Z}(112, 100, 0, 20, {home})'), 'true,false')    # 12 cases du foyer
        self.assertEqual(self.ev(f'{Z}(107, 100, 0, 20, {home})'), 'true,true')     # distance de sécurité du foyer
        self.assertEqual(self.ev(f'{Z}(115, 100, 0, 20, {home})'), 'false,false')   # 15 cases : hors zone
        self.assertEqual(self.ev(f'{Z}(130, 100, 0, 8, {home})'), 'true,false')     # près du guetteur
        self.assertEqual(self.ev(f'{Z}(130, 100, 0, 4, nil)'), 'true,true')          # groupe sans foyer
        self.assertEqual(self.ev(f'{Z}(105, 100, 2, 20, {home})'), 'false,false')   # deux étages d'écart

    def test_lines_are_deterministic_and_translated_in_english_and_french(self):
        keys = set()
        for kind in ('1', '2', '"hold"', '"shot"', '"back"', '"again"'):
            a = self.ev(f'{E}.lineKey("grp-1", "A", {kind}, 3)')
            self.assertEqual(a, self.ev(f'{E}.lineKey("grp-1", "A", {kind}, 3)'))
            keys.add(a)
        lines = self.run_lua(f'local out = {{}} for _, l in pairs({E}.LINES) do for _, s in ipairs(l) do '
                             f'out[#out + 1] = {E}.KEY_PREFIX .. s end end table.sort(out) return out')
        all_keys = set(lua_list(lines))
        self.assertTrue(keys <= all_keys)
        self.assertEqual(len(all_keys), 8)
        for lang in ('EN', 'FR'):
            tr = translations(lang)
            for k in all_keys:
                self.assertIn(k, tr, (lang, k))
                self.assertTrue(tr[k].strip(), (lang, k))
        self.assertNotEqual(translations('EN')['IGUI_LK_Warn_1_1'], translations('FR')['IGUI_LK_Warn_1_1'])


class CascadeTests(PureEncounterBase):
    WARN = 'warn = { u = "A", stage = 1, key = "pA", why = "warning A: stage 1 warned (wary)", x = 110, y = 100, z = 0 }'

    def test_warn_after_retreat_before_defense_fight_wins(self):
        rule, b, why = self.decide(f'{self.WARN}, {FIGHTER}')
        self.assertEqual((rule, b, why), ('threat', 'warn', 'warning A: stage 1 warned (wary)'))
        self.assertEqual(self.ev(f'{D}.decide(CTX({{ {self.WARN}, {FIGHTER} }})).key'), 'pA')
        # Cible d'attaque (provocation, zombie) : le combat passe avant la sommation.
        self.assertEqual(self.decide(f'{self.WARN}, {FIGHTER}, target = {{ u = "A", d = 4, reason = "provoked" }}')[1],
                         'fight')
        # Défense du foyer sans cible : la sommation d'abord ; avec une cible de défense : la défense.
        dv = 'defense = { id = "def-1", key = "def:post 110,115,0", why = "home defense def-1 hold" }'
        self.assertEqual(self.decide(f'{self.WARN}, {FIGHTER}, {dv}')[1], 'warn')
        dvt = ('defense = { id = "def-1", key = "def:post 110,115,0", why = "home defense", '
               'target = { kind = "zombie", u = "z:5", d = 2 } }')
        self.assertEqual(self.decide(f'{self.WARN}, {FIGHTER}, {dvt}')[1], 'defend')
        # Combattant à bout de nerfs : retraite avant la sommation.
        self.assertEqual(self.decide(f'{self.WARN}, {FIGHTER}, needs = {{ fear = 95 }}, '
                                     'hit = { u = "A", minute = 600 }')[1], 'retreat')
        # Non-combattant : jamais de sommation (pas d'arme à montrer).
        self.assertNotEqual(self.decide(self.WARN)[1], 'warn')
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.warn.vigil'), 'guard')
        self.assertEqual(self.ev('LivingKnox.Needs.BEHAVIOUR_ACTIVITY.warn'), 'watch')


class EncounterStack(DefenseStack):
    """Pile complète de la défense (combat, munitions, zombies), parole doublée, vue des joueurs injectée."""

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, ENC)
        h.load(srv, STACK)
        if self.mode == 'mp':
            for c in ('A', 'B'):
                h.load(c, CLIENT)
                h.load(c, ENC)          # un client MP charge aussi media/lua/server : il s'y arrête
        return h

    def mk_type(self, gtype):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "' + gtype + '", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{D}.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        if self.mode == 'mp':
            self.h.move_player('B', 101, 112)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset() LivingKnox.Routines.reset()')
        return gid

    CREW = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'false'), ('fighter', 'gunner', 'true')]

    def wary(self, gid, fact, times, who='A'):
        for _ in range(times):
            self.assertIsNotNone(self.run_lua(f'return LivingKnox.Hostility.record("{gid}", "char-{who}", "{fact}", '
                                              '{ witnessed = true })'))
        self.assertEqual(self.ev(f'LivingKnox.Hostility.get("{gid}", "char-{who}").level'), 'wary')

    def arm(self, gid, mid='m-1', rounds=5):
        npc = self.npc_of(gid, mid)
        self.run_lua(f'LivingKnox.Ammo.give("{npc}", "Base.Shotgun", {rounds}, 0) '
                     f'LivingKnox.Ammo.reload("{npc}", LivingKnox.Bodies.find("{npc}"), "Base.Shotgun")')
        return npc

    def loaded(self, npc):
        return self.ev(f'LivingKnox.Ammo.loaded(LivingKnox.Bodies.find("{npc}"), "Base.Shotgun")')

    def go(self, gid, n=1):
        for _ in range(n):
            self.run_lua(f'SEE_PLAYERS("{gid}")')
            self.dpass(1)

    def enc(self, gid, who='A'):
        return self.run_lua(f'local e = {E}.get("{gid}", "{who}") if e == nil then return nil end '
                            'return e.stage, e.peak, e.npc, e.shot')

    def until(self, gid, stage, n=20, who='A'):
        for _ in range(n):
            self.go(gid)
            e = self.enc(gid, who)
            if e is not None and e[0] == stage:
                return True
        return False


class SoloEncounterTests(EncounterStack):
    mode = 'solo'

    def test_neutral_group_warns_twice_aims_never_shoots_backs_off_and_resumes(self):
        gid = self.mk_type('deciders')
        self.jump_to(11)
        self.wary(gid, 'theft', 4)                                    # 50 - 80 = -30 : méfiant
        npc = self.arm(gid)
        self.assertEqual(self.loaded(npc), 5)
        self.run_lua('SEE.A = true')
        self.h.move_player('A', 140, 110)                              # loin : rien
        self.go(gid, 3)
        self.assertIsNone(self.enc(gid))
        self.h.move_player('A', 123, 110)                              # 13 cases du foyer : approche
        self.assertTrue(self.until(gid, 1, 4))
        self.assertEqual(self.enc(gid)[2], npc)                       # guetteur : le premier combattant (m-1)
        self.go(gid, 1)
        self.assertEqual(self.b(gid, 'm-1'), 'warn')
        self.assertEqual(self.ev('KEYS()')[:2], '1_')
        self.assertEqual(self.ev('SAID[1].names'), 'A')
        self.assertEqual(self.ev('SAID[1].band'), 'hostile')
        self.assertEqual(self.gesture(gid, 'm-1'), 'guard')           # arme en main
        e = self.run_lua(f'local e = LivingKnox.Directives.get("{npc}") return e.op, e.a')
        self.assertEqual(e[0], 'face')
        self.assertLessEqual(min(e[1], 360 - e[1]), 20)                 # vers l'est, vers le joueur
        # Délai de tolérance (méfiant : 10 s) : dernière sommation, arme braquée.
        self.go(gid, 4)
        self.assertEqual(self.enc(gid)[0], 1)
        self.assertTrue(self.until(gid, 2, 10))
        self.go(gid, 1)
        self.assertEqual(self.gesture(gid, 'm-1'), 'aim')
        self.assertEqual(self.ev('KEYS()').split()[-1][:2], '2_')
        # Distance de sécurité franchie (6 cases du foyer) : étape finale vite, arme braquée, AUCUN tir.
        self.h.move_player('A', 116, 110)
        self.assertTrue(self.until(gid, 3, 6))
        self.go(gid, 8)
        self.assertEqual(self.ev('KEYS()').split()[-1], '3_hold')
        self.assertEqual(self.gesture(gid, 'm-1'), 'aim')
        self.assertEqual((self.ev(f'{E}.stats.shots'), self.ev(f'{C}.stats.shots'), self.loaded(npc)), (0, 0, 5))
        self.assertIsNone(self.ev(f'{C}.get("{npc}")'))
        self.assertIsNone(self.ev('DAMAGES.A'))
        # Recul de trois cases : arme abaissée d'une étape ; sortie de la zone : fin, réplique « Back ».
        self.h.move_player('A', 119, 110)
        self.go(gid, 2)
        self.assertEqual(self.enc(gid)[0], 2)
        self.h.move_player('A', 125, 110)
        self.go(gid, 2)
        self.assertEqual(self.enc(gid)[:2], (0, 3))
        self.assertIn('Back', self.ev('KEYS()').split())
        self.assertNotEqual(self.b(gid, 'm-1'), 'warn')
        self.assertNotIn(self.gesture(gid, 'm-1'), ('aim',))
        # Retour dans les RESUME_MS : reprise à l'étape atteinte (« Again » puis la réplique finale).
        self.h.move_player('A', 118, 110)
        self.go(gid, 5)
        self.assertEqual(self.enc(gid)[0], 3)
        keys = self.ev('KEYS()').split()
        self.assertEqual(keys[-2:], ['Again', '3_hold'])
        self.assertEqual(self.ev(f'{E}.stats.resumed'), 1)
        self.assertEqual((self.ev(f'{E}.stats.shots'), self.ev(f'{C}.stats.shots')), (0, 0))
        # Provocation (coup vu) : targetRule rend "attack", la cascade engage (Combat.engage : « fight », ou « defend »
        # depuis son poste quand le joueur devenu hostile déclenche la défense du foyer), la rencontre est close.
        self.run_lua(f'assert(LivingKnox.Hostility.record("{gid}", "char-A", "hit", {{ witnessed = true }}))')
        self.go(gid, 2)
        self.assertIn(self.b(gid, 'm-1'), ('fight', 'defend'))
        if self.b(gid, 'm-1') == 'fight':
            self.assertEqual(self.ev(f'{C}.get("{npc}").u'), 'A')
        self.assertEqual(self.run_lua(f'local r = LivingKnox.Hostility.chooseTarget("{gid}", "{npc}", '
                                      '{ { u = "A", key = "char-A", d = 8 } }) return r.target.action, r.target.reason'),
                         ('attack', 'provoked'))
        self.assertIsNone(self.enc(gid))
        self.assertEqual(self.ev(f'{E}.stats.escalated'), 1)
        self.assertTrue(any('warning of A over at stage 3: escalated (provoked)' in line for line in self.lk()))
        self.assertEqual(self.h.errors('solo'), [])

    def test_first_strike_group_fires_one_warning_shot_after_two_heard_warnings(self):
        gid = self.mk_type('fierce')
        self.jump_to(11)
        self.wary(gid, 'gift', 3)                                     # -50 + 24 = -26 : méfiant
        npc = self.arm(gid)
        noises0 = len(lua_list(self.ev('NOISES')))
        self.run_lua('SEE.A = true')
        self.h.move_player('A', 116, 110)                              # dans la distance de sécurité
        self.assertTrue(self.until(gid, 3, 12))
        self.go(gid, 1)
        e = self.enc(gid)
        self.assertEqual((e[0], e[3]), (3, True))
        self.assertEqual(self.ev('KEYS()').split()[-1], '3_shot')
        self.assertEqual(self.ev(f'{E}.stats.shots'), 1)
        self.assertEqual(self.loaded(npc), 4)                         # une cartouche retirée
        self.assertEqual(self.ev(f'{C}.state.shots'), 1)              # son et éclair (shotEffects)
        self.assertEqual(self.ev(f'{C}.stats.shots'), 0)              # aucun tir de combat
        self.assertGreater(len(lua_list(self.ev('NOISES'))), noises0)   # bruit pour les zombies
        self.assertIsNone(self.ev('DAMAGES.A'))                       # aucun dégât
        self.assertIsNone(self.ev(f'{C}.get("{npc}")'))
        self.assertTrue(any('fired a warning shot with Base.Shotgun at A' in line for line in self.lk()))
        keys = self.ev('KEYS()').split()
        self.assertEqual([k[:1] for k in keys[:2]], ['1', '2'])        # les deux sommations d'abord
        # Au plus un coup de semonce par rencontre.
        self.go(gid, 8)
        self.assertEqual((self.ev(f'{E}.stats.shots'), self.loaded(npc)), (1, 4))
        self.assertEqual(self.gesture(gid, 'm-1'), 'aim')              # geste de tir fini
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_shot_and_no_escalation_while_the_warnings_are_not_heard(self):
        gid = self.mk_type('fierce')
        self.jump_to(11)
        self.wary(gid, 'gift', 3)
        npc = self.arm(gid)
        self.run_lua('SEE.A = true DEAF = true')
        self.h.move_player('A', 116, 110)
        self.go(gid, 25)
        self.assertEqual(self.enc(gid)[0], 1)                          # redite, pas d'escalade
        self.assertGreaterEqual(self.ev(f'{E}.stats.unheard'), 3)
        self.assertEqual((self.ev(f'{E}.stats.shots'), self.loaded(npc)), (0, 5))
        self.run_lua('DEAF = false')
        self.assertTrue(self.until(gid, 3, 12))
        self.assertEqual(self.h.errors('solo'), [])

    def test_attitude_back_to_cautious_ends_the_warning_without_a_line(self):
        gid = self.mk_type('deciders')
        self.jump_to(11)
        self.wary(gid, 'theft', 4)
        self.arm(gid)
        self.run_lua('SEE.A = true')
        self.h.move_player('A', 120, 110)
        self.assertTrue(self.until(gid, 1, 4))
        n = len(self.ev('KEYS()').split())
        for _ in range(3):
            self.run_lua(f'assert(LivingKnox.Hostility.record("{gid}", "char-A", "heal", {{ witnessed = true }}))')
        self.assertEqual(self.ev(f'LivingKnox.Hostility.get("{gid}", "char-A").level'), 'cautious')
        self.go(gid, 2)
        self.assertIsNone(self.enc(gid))
        self.assertEqual(len(self.ev('KEYS()').split()), n)
        self.assertNotEqual(self.b(gid, 'm-1'), 'warn')
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerEncounterTests(EncounterStack):
    """Serveur dédié + deux clients proches : sommation décidée par le serveur seul ; mêmes répliques, mêmes gestes et
    même regard chez A (averti) et B (simple témoin)."""

    def observed(self, gid, npc):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        for c in ('A', 'B'):
            out[c] = self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                    'local d = e and (e.op .. "@" .. tostring(e.a)) or "none" '
                                    f'return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") .. "|" .. HEARD_LIST() '
                                    'end)()')
        return out

    def test_two_observers_see_the_same_warning_sequence(self):
        gid = self.mk_type('deciders')
        self.jump_to(11)
        self.wary(gid, 'theft', 4)
        npc = self.arm(gid)
        self.run_lua('SEE.A = true SEE.B = true')                      # B : connu de personne, prudent -> pas averti
        self.h.move_player('A', 116, 110)
        rows = []
        for stage in (1, 2, 3):
            self.assertTrue(self.until(gid, stage, 12), stage)
            self.go(gid, 1)
            rows.append(self.observed(gid, npc))
        for r in rows:
            self.assertEqual(r['A'], r['B'])
        self.assertTrue(rows[0]['A'].startswith('face@'), rows[0]['A'])
        self.assertEqual([r['A'].split('|')[1] for r in rows], ['guard', 'aim', 'aim'])
        heard = rows[-1]['A'].split('|')[2].split()
        self.assertEqual([h.split(':')[1][len('IGUI_LK_Warn_'):][:1] for h in heard[:3]], ['1', '2', '3'])
        self.assertIsNone(self.enc(gid, 'B'))
        self.assertEqual((self.ev(f'{E}.stats.shots'), self.ev(f'{C}.stats.shots')), (0, 0))
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Encounters'))   # autorité seulement
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteTests(EncounterStack):
    mode = 'solo'

    def test_suite_lk_warn_is_listed(self):
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.warn", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.warn')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)

    def test_suite_lk_warn_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        for gtype in ('neutrals', 'raiders'):
            self.h.load('solo', f'shared/LivingKnox/Data/LK_Type_{gtype}.lua')
        self.h.move_player('A', 110, 110)
        self.run_lua('SEE.A = true')
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.warn", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(20000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, g in ipairs(LivingKnox.Groups.list()) do SEE_PLAYERS(g.id or g) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 20 == 19:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 2, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKW' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKW] measure stage 1:', '[LKW] measure stage 3:', '[LKW] measure held:',
                     '[LKW] measure stood down:', '[LKW] measure resumed:', '[LKW] measure warning shot:'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)   # groupes de test retirés
        self.assertEqual(self.h.errors('solo'), [])

    def test_sources_are_ascii_kahlua_safe_with_english_logs(self):
        for path in (SUITE_FILE, LUA / ENC):
            raw = path.read_bytes()
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII code in {path.name}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'\bbit32\b', r'[~&|]\s*\d',
                            r'<<|>>'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))
        self.assertTrue(all(b < 128 for b in SUITE_FILE.read_bytes()), 'non ASCII byte in the suite')


if __name__ == '__main__':
    unittest.main(verbosity=1)
