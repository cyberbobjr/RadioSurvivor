"""Tests hors jeu des seuils de danger réglables des PNJ Living Knox (LK05-T14) : options sandbox LivingKnox.* de
sandbox-options.txt et leurs traductions, lecture centralisée de LK_Config.lua (Config.danger,
Config.zombieAlertDistance) et leur emploi par LK_Alert.lua, LK_Decisions.lua, LK_Defense.lua, LK_Zombies.lua et
LK_Encounters.lua.

    python RadioSurvivor/tests/test_lk_thresholds.py

Bancs :
- fichiers : chaque option de Config.DANGER déclarée dans sandbox-options.txt (entier, bornes, défaut, page), libellé
  et infobulle EN et FR (unité « squares » / « cases ») ;
- logique pure (serveur d'un banc tests/harness.py, comme test_lk_alert.py) : chaque seuil lu depuis son option
  (doublure de getSandboxOptions():getOptionByName(nom):getValue(), nil pour une option inconnue :
  SandboxOptions.java), option absente ou invalide = valeur d'avant LK05-T14, changement relu à l'appel suivant
  (sondage) ; effet de chaque seuil sur la cascade, l'alerte, la défense, l'engagement et les sommations ;
- pile complète solo (groupe « deciders » dans la maison HOUSE, perception injectée) : un groupe face à 50 zombies
  perçus au-delà de la distance d'alerte reste dans sa routine (aucune alerte, aucune règle threat, peur inchangée) ;
  sans l'option, la même foule l'interrompt (preuve que le seuil agit) ; un zombie dans la distance donne l'alerte,
  cri au rayon de l'option.
Les doublures NE PROUVENT PAS l'API réelle (lecture d'une option par getOptionByName : base load-warnings.md) ni le
comportement en jeu (suite lk.alert, second test).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_alert as tla  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media'
SANDBOX_FILE = MEDIA / 'sandbox-options.txt'
TRANSLATE = MEDIA / 'lua' / 'shared' / 'Translate'
CONFIG = MEDIA / 'lua' / 'shared' / 'LivingKnox' / 'LK_Config.lua'

A = 'LivingKnox.Alert'
D = 'LivingKnox.Decisions'
DF = 'LivingKnox.Defense'
ZM = 'LivingKnox.Zombies'
EN = 'LivingKnox.Encounters'
C = 'LivingKnox.Config'

# Options attendues : (min, max, défaut de sandbox-options.txt), valeur d'avant LK05-T14 (None : aucune limite).
OPTIONS = {
    'ZombieAlertDistance': ((1, 30, 10), None),
    'AlertReach': ((5, 60, 20), 30),
    'AlertShoutZombie': ((1, 30, 10), 15),
    'FleeDistance': ((1, 20, 4), 6),
    'FleeDistanceAfraid': ((1, 30, 8), 12),
    # LK06-T14 : une option par rôle (remplace ZombieEngageDistance, défaut 4, repli 5), défaut et repli 10.
    'ZombieEngageDeputy': ((1, 15, 10), 10),
    'ZombieEngageFighter': ((1, 15, 10), 10),
    'ZombieEngageScout': ((1, 15, 10), 10),
    'ZombieEngageMedic': ((1, 15, 10), 10),
    'ZombieEngageWorker': ((1, 15, 10), 10),
    'ZombieEngageBreaker': ((1, 15, 10), 10),
    'DefenseRadius': ((3, 30, 8), 12),
    'DefenseWithdrawRatio': ((2, 10, 3), 3),
    'RetreatDangerDistance': ((2, 30, 8), 15),
    'ReinforcementRadius': ((3, 50, 15), 20),
    'WarnHomeRadius': ((4, 30, 14), 14),
    'WarnGroupRadius': ((2, 30, 10), 10),
}

# getSandboxOptions():getOptionByName(nom) : nil pour une option inconnue, sinon getValue() ; autres options : repli
# sur la doublure précédente (s'il y en a une).
SANDBOX = r'''
LK_OPTS = {}
local prevOptions = getSandboxOptions
getSandboxOptions = function()
    local prev = prevOptions ~= nil and prevOptions() or nil
    return { getOptionByName = function(_, name)
        local v = LK_OPTS[name]
        if v ~= nil then return { getValue = function() return v end } end
        if prev ~= nil then return prev:getOptionByName(name) end
        return nil
    end }
end
function OPT(name, v) LK_OPTS["LivingKnox." .. name] = v end
'''


def sandbox_blocks() -> dict:
    text = SANDBOX_FILE.read_text(encoding='utf-8')
    out = {}
    for name, body in re.findall(r'option\s+LivingKnox\.(\w+)\s*\{(.*?)\}', text, flags=re.S):
        out[name] = dict(re.findall(r'(\w+)\s*=\s*([^,\n]+),', body))
    return out


def defaults_lua() -> str:
    return ''.join(f'OPT("{n}", {spec[2]})\n' for n, (spec, _) in OPTIONS.items())


class FileTests(unittest.TestCase):
    def test_every_threshold_is_an_integer_option_of_the_living_knox_page(self):
        blocks = sandbox_blocks()
        for name, ((lo, hi, default), _) in OPTIONS.items():
            b = blocks.get(name)
            self.assertIsNotNone(b, name)
            self.assertEqual(b['type'].strip(), 'integer', name)
            self.assertEqual((int(b['min']), int(b['max']), int(b['default'])), (lo, hi, default), name)
            self.assertEqual(b['page'].strip(), 'LivingKnox', name)
            self.assertEqual(b['translation'].strip(), 'LivingKnox_' + name, name)
            self.assertTrue(lo <= default <= hi, name)

    def test_config_table_matches_the_file(self):
        code = CONFIG.read_text(encoding='utf-8')
        block = code[code.index('Config.DANGER = {'):]
        block = block[:block.index('\n}')]
        found = {n: (int(a), int(b), int(c)) for n, a, b, c in
                 re.findall(r'(\w+) = \{ (\d+), (\d+), (\d+) \}', block)}
        self.assertEqual(found, {n: spec for n, (spec, _) in OPTIONS.items()})

    def test_label_and_tooltip_in_english_and_french_with_the_unit(self):
        for lang, unit in (('EN', 'squares'), ('FR', 'cases')):
            data = json.loads((TRANSLATE / lang / 'Sandbox.json').read_text(encoding='utf-8'))
            for name in OPTIONS:
                label = data.get(f'Sandbox_LivingKnox_{name}')
                tip = data.get(f'Sandbox_LivingKnox_{name}_tooltip')
                self.assertTrue(label and tip, (lang, name))
                if name != 'DefenseWithdrawRatio':
                    self.assertIn(f'({unit})', label, (lang, name))
                    self.assertIn(unit, tip, (lang, name))


class PureThresholdBase(tla.PureAlertBase):
    def setUp(self):
        super().setUp()
        self.run_lua('require "LivingKnox/LK_Zombies" require "LivingKnox/LK_Defense" '
                     'require "LivingKnox/LK_Encounters"')
        self.run_lua(SANDBOX)

    def opt(self, name, value):
        self.run_lua(f'OPT("{name}", {"nil" if value is None else value})')

    def values(self):
        return self.run_lua(
            f'local r, rz = {DF}.radii() local w, h = {DF}.ratios() local hz, hs, mz, ms = {EN}.radii() '
            f'return {{ zombie = {C}.zombieAlertDistance(), reach = {A}.reach(), shout = {A}.shoutRadius("zombie"), '
            f'flee = {D}.fleeDist(), afraid = {D}.fleeDistAfraid(), engage = {ZM}.engageRange(), defense = r, '
            f'defenseZ = rz, withdraw = w, hold = h, retreat = {D}.retreatDist(), help = {D}.helpRadius(), '
            f'reinforce = {DF}.reinforceRadius(), homeZone = hz, homeSafe = hs, memberZone = mz, memberSafe = ms }}')

    def table(self):
        t = self.values()
        return {k: t[k] for k in ('zombie', 'reach', 'shout', 'flee', 'afraid', 'engage', 'defense', 'defenseZ',
                                  'withdraw', 'hold', 'retreat', 'help', 'reinforce', 'homeZone', 'homeSafe',
                                  'memberZone', 'memberSafe')}


class ReadTests(PureThresholdBase):
    def test_missing_options_keep_the_values_from_before(self):
        self.assertEqual(self.table(), {'zombie': None, 'reach': 30, 'shout': 15, 'flee': 6, 'afraid': 12,
                                        'engage': 10, 'defense': 12, 'defenseZ': 12, 'withdraw': 3, 'hold': 2,
                                        'retreat': 15, 'help': 20, 'reinforce': 30, 'homeZone': 14, 'homeSafe': 7,
                                        'memberZone': 10, 'memberSafe': 5})
        self.assertEqual(self.ev(f'{A}.shoutRadius("intruder")'), 20)
        self.assertEqual(self.ev(f'{A}.shoutRadius("hostile")'), 30)

    def test_each_threshold_read_from_its_option(self):
        for name, value in (('ZombieAlertDistance', 25), ('AlertReach', 21), ('AlertShoutZombie', 9),
                            ('FleeDistance', 3), ('FleeDistanceAfraid', 7), ('ZombieEngageFighter', 6),
                            ('DefenseRadius', 9), ('DefenseWithdrawRatio', 4), ('RetreatDangerDistance', 11),
                            ('ReinforcementRadius', 13), ('WarnHomeRadius', 17), ('WarnGroupRadius', 9)):
            self.opt(name, value)
        self.assertEqual(self.table(), {'zombie': 25, 'reach': 21, 'shout': 9, 'flee': 3, 'afraid': 7,
                                        'engage': 6, 'defense': 9, 'defenseZ': 9, 'withdraw': 4, 'hold': 3,
                                        'retreat': 11, 'help': 13, 'reinforce': 21, 'homeZone': 17, 'homeSafe': 8,
                                        'memberZone': 9, 'memberSafe': 4})
        self.assertEqual(self.ev(f'{A}.shoutRadius("intruder")'), 20)   # cri d'un intrus ou d'un hostile : inchangé
        # Distance d'alerte plus courte : l'engagement et le recensement des zombies du foyer n'y vont jamais au-delà.
        self.opt('ZombieAlertDistance', 5)
        t = self.table()
        self.assertEqual((t['engage'], t['defense'], t['defenseZ']), (5, 9, 5))

    def test_engage_distance_per_role(self):
        # LK06-T14 : une option par rôle de Config.GROUP_ROLES ; rôle inconnu (autre mod) ou absent : fighter.
        roles = lua_list(self.run_lua(f'return {C}.GROUP_ROLES'))
        self.assertEqual(sorted(roles), sorted(self.run_lua(f'local out = {{}} for r in pairs({C}.ZOMBIE_ENGAGE) do '
                                                            'out[#out + 1] = r end return out').values()))
        for i, role in enumerate(roles):
            self.opt('ZombieEngage' + role.capitalize(), 2 + i)
        for i, role in enumerate(roles):
            self.assertEqual(self.ev(f'{ZM}.engageRange(nil, "{role}")'), 2 + i, role)
        fighter = 2 + roles.index('fighter')
        self.assertEqual(self.ev(f'{ZM}.engageRange(nil, "sniper")'), fighter)   # rôle d'un autre mod
        self.assertEqual(self.ev(f'{ZM}.engageRange()'), fighter)                # PNJ hors groupe
        self.opt('ZombieAlertDistance', 3)
        self.assertEqual(self.ev(f'{ZM}.engageRange(nil, "worker")'), 3)         # jamais au-delà de l'alerte

    def test_defaults_of_the_file_and_polling(self):
        self.run_lua(defaults_lua())
        self.assertEqual(self.table(), {'zombie': 10, 'reach': 20, 'shout': 10, 'flee': 4, 'afraid': 8,
                                        'engage': 10, 'defense': 8, 'defenseZ': 8, 'withdraw': 3, 'hold': 2,
                                        'retreat': 8, 'help': 15, 'reinforce': 20, 'homeZone': 14, 'homeSafe': 7,
                                        'memberZone': 10, 'memberSafe': 5})
        # Changement en cours de partie (aucun événement) : relu à l'appel suivant.
        self.opt('FleeDistance', 2)
        self.assertEqual(self.ev(f'{D}.fleeDist()'), 2)
        self.opt('FleeDistance', None)
        self.assertEqual(self.ev(f'{D}.fleeDist()'), 6)

    def test_invalid_value_keeps_the_previous_value_with_one_warning(self):
        for bad in (0, 21, 4.5, '"x"'):
            self.opt('FleeDistance', bad)
            self.assertEqual(self.ev(f'{D}.fleeDist()'), 6, bad)
            self.assertEqual(self.ev(f'{D}.fleeDist()'), 6, bad)
        warnings = [line for line in self.h.logs(self.srv) if 'LivingKnox.FleeDistance' in line]
        self.assertEqual(len(warnings), 4, warnings)
        self.assertTrue(all('previous value 6 used' in line for line in warnings), warnings)
        self.opt('ZombieAlertDistance', 99)
        self.assertIsNone(self.ev(f'{C}.zombieAlertDistance()'))
        self.assertIsNone(self.ev(f'{C}.danger("Unknown", nil)'))


class EffectTests(PureThresholdBase):
    def test_flee_distances_drive_the_cascade(self):
        decide = 'local o = {D}.decide(CTX({{ {over} }})) return o.rule, o.b'
        hurt = 'threat = ZOMBIE(5), health = 0.4, atHome = false'   # LK06-T07 : seul un membre blessé ou apeuré fuit
        self.assertEqual(self.run_lua(decide.format(D=D, over=hurt)), ('threat', 'flee'))
        self.opt('FleeDistance', 4)
        self.assertEqual(self.run_lua(decide.format(D=D, over=hurt)), ('threat', 'watch'))
        afraid = 'threat = ZOMBIE(9), atHome = false, needs = { fear = 75, hunger = 0, thirst = 0, fatigue = 0 }'
        self.assertEqual(self.run_lua(decide.format(D=D, over=afraid)), ('threat', 'flee'))
        self.opt('FleeDistanceAfraid', 8)
        self.assertEqual(self.run_lua(decide.format(D=D, over=afraid)), ('threat', 'watch'))
        # Peur sans menace perçue : fuite de la source seulement à FleeDistanceAfraid.
        fear = 'needs = { fear = 90, hunger = 0, thirst = 0, fatigue = 0 }, fearFrom = { x = 109, y = 100, z = 0 }'
        self.assertEqual(self.run_lua(decide.format(D=D, over=fear)), ('fear', 'rest'))
        self.opt('FleeDistanceAfraid', 9)
        self.assertEqual(self.run_lua(decide.format(D=D, over=fear)), ('fear', 'flee'))

    def test_retreat_danger_and_reinforcement_radius(self):
        ctx = f'{D}.retreatOf(CTX({{ threat = ZOMBIE(12), health = 0.2, atHome = false }}))'
        self.assertIsNotNone(self.ev(ctx))
        self.opt('RetreatDangerDistance', 10)
        self.assertIsNone(self.ev(ctx))
        self.run_lua(f'{D}.state.help = {{ ["grp-1"] = {{ minute = 600, ox = 100, oy = 100, oz = 0 }} }}')
        self.assertIsNotNone(self.ev(f'{D}.helpFor("grp-1", 115.5, 100.5, 0, 601)'))
        self.opt('ReinforcementRadius', 13)
        self.assertIsNone(self.ev(f'{D}.helpFor("grp-1", 115.5, 100.5, 0, 601)'))
        self.assertIsNotNone(self.ev(f'{D}.helpFor("grp-1", 112.5, 100.5, 0, 601)'))

    def test_zombies_beyond_the_alert_distance_are_ignored_by_cascade_and_alert(self):
        per = ('{ stale = false, z = { { o = 5, x = 106, y = 100, z = 0, s = true, h = false, d = 6 }, '
               '{ o = 6, x = 109, y = 100, z = 0, s = false, h = true, d = 9 }, '
               '{ o = 7, x = 112, y = 100, z = 0, s = true, h = false, d = 12 } }, p = {} }')
        keys = (f'local t = {{}} for i, e in ipairs({D}.threatsOf({per}, {{}})) do t[i] = e.key end '
                f'local u = {{}} for i, e in ipairs({A}.threatsOf({per}, {{}}, HOME)) do u[i] = e.key end '
                'return table.concat(t, " ") .. "|" .. table.concat(u, " ")')
        # Sans option : tous les zombies perçus pour la cascade ; l'alerte garde déjà ses rayons (10 / 15 du foyer).
        self.assertEqual(self.run_lua(keys), 'z5 z6 z7|z:5 z:6 z:7')
        self.opt('ZombieAlertDistance', 8)
        self.assertEqual(self.run_lua(keys), 'z5|z:5')
        self.opt('ZombieAlertDistance', 30)
        self.assertEqual(self.run_lua(keys), 'z5 z6 z7|z:5 z:6 z:7')

    def test_alert_reach(self):
        self.note('zombie', 'z:5', 600, x=105, y=100)
        member = f'{A}.forMember("grp-1", 127.5, 100.5, 0, false, 601)'
        self.assertIsNotNone(self.ev(member))
        self.opt('AlertReach', 20)
        self.assertIsNone(self.ev(member))
        self.assertIsNotNone(self.ev(f'{A}.forMember("grp-1", 127.5, 100.5, 0, true, 601)'))   # au foyer

    def test_defense_ratio_and_census_radius(self):
        assess = f'local p = {DF}.assess({{t}}, 2, {{prev}}) return p'
        self.assertEqual(self.run_lua(assess.format(t=8, prev='nil')), 'withdraw')   # 8 > 3 x 2
        self.opt('DefenseWithdrawRatio', 4)
        self.assertEqual(self.run_lua(assess.format(t=8, prev='nil')), 'hold')       # 8 <= 4 x 2
        self.assertEqual(self.run_lua(assess.format(t=7, prev='"withdraw"')), 'withdraw')   # retour à 3 x 2
        self.assertEqual(self.run_lua(assess.format(t=6, prev='"withdraw"')), 'hold')
        # Recensement autour du foyer (100, 100) : zombies à 5, 9 et 11 cases.
        self.run_lua(r'''
            local function zb(id, x, y)
                return { id = id, getX = function() return x end, getY = function() return y end,
                    getZ = function() return 0 end }
            end
            local list = { zb(1, 105.5, 100.5), zb(2, 109.5, 100.5), zb(3, 100.5, 111.5) }
            getCell = function() return { getZombieList = function() return {
                size = function() return #list end, get = function(_, i) return list[i + 1] end } end } end
            LivingKnox.Zombies.isVanilla = function() return true end
            LivingKnox.Zombies.keyOf = function(z) return "z:" .. z.id end
            G_HOME = { type = "settlers", home = { x = 100, y = 100, z = 0 } }
        ''')
        census = f'return {DF}.census("grp-1", G_HOME, {{}}).zombies'
        self.assertEqual(self.run_lua(census), 3)               # repli : 12 cases
        self.opt('DefenseRadius', 9)
        self.assertEqual(self.run_lua(census), 2)
        self.opt('ZombieAlertDistance', 6)
        self.assertEqual(self.run_lua(census), 1)               # zombies : jamais au-delà de la distance d'alerte

    def test_warning_zones(self):
        zones = f'return {EN}.zones(112, 100, 0, {{d}}, nil)'
        self.assertEqual(self.run_lua(zones.format(d=12)), (False, False))
        self.opt('WarnGroupRadius', 13)
        self.assertEqual(self.run_lua(zones.format(d=12)), (True, False))
        self.assertEqual(self.run_lua(zones.format(d=6)), (True, True))   # sécurité : 13 / 2 = 6
        home = f'return {EN}.zones(116, 100, 0, 30, {{ x = 100, y = 100, z = 0 }})'
        self.assertEqual(self.run_lua(home), (False, False))
        self.opt('WarnHomeRadius', 16)
        self.assertEqual(self.run_lua(home), (True, False))


class CrowdStack(tla.AlertStack):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', SANDBOX)
        h.load('solo', defaults_lua())
        h.load('solo', r'''
            -- Foule : n zombies vus autour du membre id, de dmin à dmin + 14 cases (identifiants fictifs).
            function CROWD(id, n, dmin)
                local body = LivingKnox.Bodies.find(id)
                local bx, by = body:getX(), body:getY()
                local z = {}
                for i = 1, n do
                    local d = dmin + (i % 15)
                    local a = i * 2 * math.pi / n
                    z[i] = { o = 7000 + i, x = math.floor(bx + d * math.cos(a)), y = math.floor(by + d * math.sin(a)),
                        z = 0, a = 1, s = true, h = false, d = d }
                end
                PERCEPTION[id] = { ms = 0, age = 0, stale = false, nz = n, seen = n, heard = 0, p = {}, z = z, n = {} }
            end
        ''')
        return h

    def crowd_all(self, gid, n=50, dmin=12):
        for m in ('m-1', 'm-2', 'm-3'):
            self.run_lua(f'CROWD(MEMBER_NPC("{gid}", "{m}"), {n}, {dmin})')

    def rules(self, gid):
        return {m: self.run_lua(f'local s = {D}.get(MEMBER_NPC("{gid}", "{m}")) return s and s.rule or nil')
                for m in ('m-1', 'm-2', 'm-3')}

    def fears(self, gid):
        return [self.ev(f'{D}.needsOf("{gid}", "{m}").fear') for m in ('m-1', 'm-2', 'm-3')]


class CrowdTests(CrowdStack):
    def test_group_facing_fifty_zombies_beyond_the_alert_distance_keeps_its_routine(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(3)
        before = self.rules(gid)
        self.assertTrue(all(r in ('duty', 'routine') for r in before.values()), before)
        self.crowd_all(gid, 50, 12)                       # 12 à 26 cases, distance d'alerte : 10
        self.assertEqual(self.ev('#PERCEPTION[MEMBER_NPC("' + gid + '", "m-2")].z'), 50)
        for _ in range(10):
            self.dpass(2)
            rules = self.rules(gid)
            self.assertTrue(all(r in ('duty', 'routine') for r in rules.values()), rules)
            self.assertIsNone(self.ev(f'{A}.get("{gid}")'))
        self.assertEqual(self.ev(f'{A}.stats.raised'), 0)
        self.assertEqual(self.ev('#BARKS'), 0)
        self.assertEqual(self.fears(gid), [0, 0, 0])
        self.assertEqual(self.h.errors('solo'), [])

    def test_without_the_option_the_same_crowd_interrupts_the_routine(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(3)
        self.run_lua('OPT("ZombieAlertDistance", nil)')   # comportement d'avant LK05-T14 : tout zombie perçu
        self.crowd_all(gid, 50, 12)
        self.dpass(4)
        rules = self.rules(gid)
        self.assertTrue(all(r == 'threat' for r in rules.values()), rules)
        self.assertTrue(any(f > 0 for f in self.fears(gid)), self.fears(gid))

    def test_zombie_within_the_distance_raises_the_alert_with_the_shout_radius_of_the_option(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(3)
        self.crowd_all(gid, 50, 12)
        self.dpass(2)
        x, y = self.body_xy(gid, 'm-1')
        self.run_lua(f'local p = PERCEPTION[MEMBER_NPC("{gid}", "m-1")] '
                     f'p.z[#p.z + 1] = {{ o = 950, x = {int(x) + 6}, y = {int(y)}, z = 0, a = 1, s = true, '
                     'h = false, d = 6 }')
        self.dpass(3)
        self.assertEqual(self.ev(f'{A}.stats.raised'), 1)
        self.assertEqual(self.ev(f'{A}.get("{gid}").key'), 'z:950')
        alert_noises = [n for n in lua_list(self.ev('NOISES')) if n.src is None and n.r == 10]
        self.assertEqual(len(alert_noises), 1)
        self.assertEqual(self.h.errors('solo'), [])


class SourceTests(unittest.TestCase):
    def test_no_hard_coded_threshold_left_in_the_modules(self):
        lua = MEDIA / 'lua' / 'server' / 'LivingKnox'
        checks = {
            'LK_Alert.lua': [r'cfg\(\)\.REACH\b(?!\))', r'c\.SHOUT\[a\.kind\]'],
            'LK_Decisions.lua': [r'cfg\(\)\.FLEE_DIST\b(?!\))', r'cfg\(\)\.FLEE_DIST_AFRAID\b(?!\))', r't\.flee and t\.d <= c\.DIST\)',
                                 r'> c\.RADIUS'],
            'LK_Defense.lua': [r'c\.THREAT_RADIUS', r'c\.WITHDRAW_RATIO \*', r'c\.HOLD_RATIO \*',
                               r'<= cfg\(\)\.REINFORCE_RADIUS'],
            'LK_Zombies.lua': [r'local range = cfg\(\)\.DEFEND_RANGE'],
            'LK_Encounters.lua': [r'd <= c\.MEMBER_ZONE', r'hd <= c\.HOME_ZONE'],
        }
        for name, patterns in checks.items():
            code = re.sub(r'--[^\n]*', '', (lua / name).read_text(encoding='utf-8'))
            for pattern in patterns:
                self.assertIsNone(re.search(pattern, code), (name, pattern))


if __name__ == '__main__':
    unittest.main()
