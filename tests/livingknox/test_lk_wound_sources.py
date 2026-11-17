"""Tests hors jeu des sources de blessure de Living Knox (LK21-T02, ADR adr-blessures-soins.md D03) :
server/LivingKnox/LK_WoundSources.lua (registre, classement), server/LivingKnox/LK_WoundContext.lua (hasard et options
du jeu) et un fichier par source (server/LivingKnox/Wounds/LK_WoundSource_<Id>.lua).

    python tests/livingknox/test_lk_wound_sources.py

Vrai Lua du mod sous lupa (Lua 5.1, `next` retiré comme dans Kahlua), avec le modèle pur des plaies et ses types
(shared/LivingKnox/LK_Wounds.lua, Wounds/). Doublures (elles NE PROUVENT PAS l'API réelle) : `instanceof`,
`WeaponCategory` (champs de J/scripting/objects/WeaponCategory.java:13-20), arme (`isOfWeaponCategory`,
HandWeapon.java:1158 ; `isAimedFirearm`, :1079), zombie (`isCrawling`, IsoZombie.java:3998), `ZombRand`,
`getSandboxOptions`, `getGameTime`. Hasard fixé (ctx.rnd) : chaque cas est déterministe.

Règles vanilla vérifiées (Java décompilé 42.22, `J/` = E:/pz-source-42.22/java/zombie/) :
- zombie (BodyDamage.AddRandomDamageFromZombie, `J/characters/BodyDamage/BodyDamage.java:1101-1346`) : issue
  griffure / lacération / morsure, parties d'un zombie debout (:1178-1206) et rampant (:1208-1209) ;
- armes (BodyDamage.DamageFromWeapon, `:1014-1094`) : contondant (Blunt, SmallBlunt) puis arme à feu visée, sinon
  tranchant ; tranchant 1/6 profonde, 1/3 coupure, sinon griffure ; contondant 1/4 coupure, sinon griffure ; balle ;
  partie tirée de Hand_L à Foot_R (:1030-1032) ;
- feu (IsoGameCharacter.SetOnFire, `J/characters/IsoGameCharacter.java:7499-7510` ; BodyPart.setBurned :1204-1217) ;
- verre brisé (`J/ai/states/ClimbThroughWindowState.java:532`, BodyDamage.setScratchedWindow :1631-1638,
  BodyPart.SetScratchedWindow :846-873) : 1 sur 2, Hand_L à ForeArm_R, 1 sur 7 éclats, sinon griffure 12-20 qui saigne.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
LK_LUA = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'
LK_SHARED = LK_LUA / 'shared'
LK_SERVER = LK_LUA / 'server'
KIND_DIR = LK_SHARED / 'LivingKnox' / 'Wounds'
SOURCE_DIR = LK_SERVER / 'LivingKnox' / 'Wounds'
MODULES = [LK_SERVER / 'LivingKnox' / 'LK_WoundSources.lua', LK_SERVER / 'LivingKnox' / 'LK_WoundContext.lua',
           *sorted(SOURCE_DIR.glob('*.lua'))]
W = 'LivingKnox.Wounds'
SOURCES = ['zombie', 'blunt', 'firearm', 'fire', 'glass', 'blade']   # ordre du registre
PARTS = ['Hand_L', 'Hand_R', 'ForeArm_L', 'ForeArm_R', 'UpperArm_L', 'UpperArm_R', 'Torso_Upper', 'Torso_Lower',
         'Head', 'Neck', 'Groin', 'UpperLeg_L', 'UpperLeg_R', 'LowerLeg_L', 'LowerLeg_R', 'Foot_L', 'Foot_R']

DOUBLES = r'''
CLASSES = {}
function instanceof(o, name) return type(o) == "table" and o.classes ~= nil and o.classes[name] == true end
WeaponCategory = { AXE = "Axe", BLUNT = "Blunt", IMPROVISED = "Improvised", LONG_BLADE = "LongBlade",
    SMALL_BLADE = "SmallBlade", SMALL_BLUNT = "SmallBlunt", SPEAR = "Spear", UNARMED = "Unarmed" }
-- class(nom) : doublure rattachee a sa classe Java (methodes controlees par test_doubles_api).
local function class(name) local c = { __javaName = name } c.__index = c return c end
local Weapon = class("HandWeapon")
function Weapon:isOfWeaponCategory(c)
    if c == nil then error("No implementation found for isOfWeaponCategory with argument nil", 2) end
    return self.cats[c] == true
end
function Weapon:isAimedFirearm() return self.aimed == true end
function WEAPON(cats, aimed)
    local set = {}
    for _, c in ipairs(cats) do set[c] = true end
    return setmetatable({ cats = set, aimed = aimed == true }, Weapon)
end
local Zed = class("IsoZombie")
function Zed:isCrawling() return self.crawling == true end
function ZOMBIE(crawling) return setmetatable({ classes = { IsoZombie = true }, crawling = crawling }, Zed) end
function PLAYER() return { classes = { IsoPlayer = true, IsoGameCharacter = true } } end
ZombRand = function(n) return math.floor(n * 0.25) end
OPTIONS = {}
getSandboxOptions = function()
    return { getOptionByName = function(_, name)
        local v = OPTIONS[name]
        if v == nil then return nil end
        return { getValue = function() return v end }
    end }
end
MPD, AGE = 90, 30.5
getGameTime = function()
    return { getMinutesPerDay = function() return MPD end, getWorldAgeHours = function() return AGE end }
end
-- seq(t) : tirages déterministes, rejoués en boucle ; lcg() : suite pseudo-aléatoire reproductible.
function seq(t) local i = 0 return function() i = i % #t + 1 return t[i] end end
function lcg(seed) local s = seed return function() s = (s * 1103515245 + 12345) % 2147483648 return s / 2147483648 end end
'''


class WoundSourceTests(unittest.TestCase):
    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;{LK_SERVER.as_posix()}/?.lua;]]; '
                        'package.cpath = ""')
        self.rt.execute(DOUBLES)
        self.rt.execute('require "LivingKnox/LK_Wounds"')
        for path in sorted(KIND_DIR.glob('*.lua')):
            self.rt.execute(f'require "LivingKnox/Wounds/{path.stem}"')
        for path in MODULES:
            self.rt.execute(path.read_text(encoding='utf-8'))

    def ev(self, code):
        return self.rt.execute('return ' + code)

    def run_lua(self, code):
        return self.rt.execute(code)

    def made(self, hit, rnd):
        """Plaies faites par le coup hit (texte Lua) avec les tirages rnd : [(part, kind, bleed > 0, time)], source."""
        self.run_lua(f'L = {{}}; C = {{ rnd = {rnd} }}; ADDED, SRC = {W}.fromHit(L, {hit}, C)')
        out = []
        for i in range(1, self.ev('#ADDED') + 1):
            w = self.ev(f'ADDED[{i}]')
            out.append((w.part, w.kind, w.bleed > 0, w.time))
        return out, self.ev('SRC')

    # ------------------------------------------------------------------ registre et classement
    def test_every_source_registered_from_its_own_file(self):
        files = sorted(p.stem for p in SOURCE_DIR.glob('*.lua'))
        self.assertEqual(files, sorted(f'LK_WoundSource_{s.capitalize()}' for s in SOURCES))
        ids = [self.ev(f'{W}.sourceList[{i}].id') for i in range(1, self.ev(f'#{W}.sourceList') + 1)]
        self.assertEqual(ids, SOURCES)

    def test_classifier_by_attacker_and_weapon_categories(self):
        cases = [
            ('{ attacker = ZOMBIE(false) }', 'zombie'),
            ('{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.BLUNT }) }', 'blunt'),          # batte
            ('{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.SMALL_BLUNT }) }', 'blunt'),    # marteau
            ('{ attacker = PLAYER(), weapon = WEAPON({}, true) }', 'firearm'),                        # pistolet
            ('{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.SMALL_BLADE }) }', 'blade'),    # couteau
            ('{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.AXE }) }', 'blade'),            # hache
            ('{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.BLUNT }, true) }', 'blunt'),    # vanilla : contondant d'abord
            ('{ attacker = ZOMBIE(false), weapon = WEAPON({ WeaponCategory.BLUNT }) }', 'blunt'),
            ('{ attacker = PLAYER(), source = "glass" }', 'glass'),
            ('{ source = "fire" }', 'fire'),
        ]
        for hit, expected in cases:
            with self.subTest(hit=hit):
                self.assertEqual(self.ev(f'{W}.classify({hit}).id'), expected)
        for hit in ('{}', '{ attacker = PLAYER() }', 'nil', '{ source = "nope" }'):
            with self.subTest(hit=hit):
                self.assertIsNone(self.ev(f'{W}.classify({hit})'))
        # Aucune source : le coup ne fait que des dégâts.
        self.assertEqual(self.made('{ attacker = PLAYER() }', 'seq({ 0.5 })'), ([], None))

    def test_new_source_without_engine_change(self):
        self.run_lua(f'{W}.registerSource("acid", {{ order = 5, match = function(hit) return hit.acid end, '
                     'wounds = function() return { { part = "Hand_L", kind = "burn" } } end })')
        self.assertEqual(self.made('{ acid = true, attacker = ZOMBIE(false) }', 'seq({ 0.5 })')[0][0][:2],
                         ('Hand_L', 'burn'))
        for bad in ('"x", { order = 1 }', '"x", { order = 1, wounds = 3 }', '"x", { wounds = function() end }',
                    '"x", { order = 1, wounds = function() end, match = 1 }'):
            with self.subTest(bad=bad):
                self.assertFalse(self.ev(f'(pcall({W}.registerSource, {bad}))'))

    # ------------------------------------------------------------------ zombie
    def test_zombie_scratch_laceration_and_bite_follow_the_issue(self):
        # rnd 0.5 : pas 1 fois sur 10 (5 >= 1), partie Hand_L..Neck d'index 1 + floor(0.5 x 10) = 6 : UpperArm_R.
        for issue, kind, bleeds in (('scratch', 'scratch', False), ('laceration', 'laceration', True),
                                    ('bite', 'bite', True)):
            with self.subTest(issue=issue):
                made, src = self.made(f'{{ attacker = ZOMBIE(false), issue = "{issue}" }}', 'seq({ 0.5 })')
                self.assertEqual(src, 'zombie')
                self.assertEqual([m[:3] for m in made], [('UpperArm_R', kind, bleeds)])
        self.assertIs(self.ev('ADDED[1].infected'), True)               # morsure infectée dès la blessure

    def test_zombie_parts_standing_head_redirect_and_crawling_legs(self):
        # 1 fois sur 10 (rnd 0.05) : Hand_L..Groin ; rnd 0.99 -> Groin.
        self.assertEqual(self.made('{ attacker = ZOMBIE(false), issue = "scratch" }', 'seq({ 0.05, 0.99 })')[0][0][0],
                         'Groin')
        # Tête (index 9 : rnd 0.8) puis tirage 0.5 x 100 < 71 : la tête reste.
        self.assertEqual(self.made('{ attacker = ZOMBIE(false), issue = "scratch" }', 'seq({ 0.5, 0.8, 0.5 })')[0][0][0],
                         'Head')
        # Cou (rnd 0.9) puis 0.8 x 100 >= 71 : partie retirée de Hand_L..Torso_Lower (0.0 -> Hand_L).
        self.assertEqual(self.made('{ attacker = ZOMBIE(false), issue = "scratch" }',
                                   'seq({ 0.5, 0.9, 0.8, 0.0 })')[0][0][0], 'Hand_L')
        # Rampant : jambes ; 1 fois sur 10 de Groin à Foot_R, sinon de UpperLeg_L à Foot_R.
        self.assertEqual(self.made('{ attacker = ZOMBIE(true), issue = "bite" }', 'seq({ 0.5, 0.0 })')[0][0][0],
                         'UpperLeg_L')
        self.assertEqual(self.made('{ attacker = ZOMBIE(true), issue = "bite" }', 'seq({ 0.05, 0.0 })')[0][0][0],
                         'Groin')
        # Répartition sur 4000 attaques : debout jamais plus bas que Groin, rampant toujours aux jambes.
        self.run_lua(f'R = lcg(7); C = {{ rnd = R }}; STAND, CRAWL = {{}}, {{}}; '
                     f'for i = 1, 4000 do local L = {{}} {W}.fromHit(L, {{ attacker = ZOMBIE(false), issue = "scratch" }}, C) '
                     'STAND[L[1].part] = (STAND[L[1].part] or 0) + 1 '
                     f'L = {{}} {W}.fromHit(L, {{ attacker = ZOMBIE(true), issue = "scratch" }}, C) '
                     'CRAWL[L[1].part] = (CRAWL[L[1].part] or 0) + 1 end')
        stand = {p: self.ev(f'STAND["{p}"] or 0') for p in PARTS}
        crawl = {p: self.ev(f'CRAWL["{p}"] or 0') for p in PARTS}
        self.assertEqual(sum(stand[p] for p in PARTS[11:]), 0)
        self.assertEqual(sum(crawl[p] for p in PARTS[:10]), 0)
        self.assertGreater(stand['Groin'], 0)
        # Tête et cou : 1/10 x 70 % du tirage d'une partie sur 10 (ou 11), soit environ 7 % chacun.
        self.assertLess(stand['Head'], 4000 * 0.1)
        self.assertGreater(stand['Torso_Upper'], stand['Head'])

    def test_zombie_without_issue_rolls_the_vanilla_thresholds(self):
        self.run_lua('LivingKnox.Config = LivingKnox.Config or {}; LivingKnox.Config.ZOMBIES = { BITE = 85, LACERATION = 65 }')
        # Tirages dans l'ordre du vanilla : lacération (> 65), morsure (> 85, l'emporte), puis partie.
        self.assertEqual(self.made('{ attacker = ZOMBIE(false) }', 'seq({ 0.1, 0.9, 0.5 })')[0][0][1], 'bite')
        self.assertEqual(self.made('{ attacker = ZOMBIE(false) }', 'seq({ 0.7, 0.1, 0.5 })')[0][0][1], 'laceration')
        self.assertEqual(self.made('{ attacker = ZOMBIE(false) }', 'seq({ 0.1, 0.1, 0.5 })')[0][0][1], 'scratch')

    # ------------------------------------------------------------------ armes
    def test_knife_deep_one_in_six_laceration_one_in_three_else_scratch(self):
        knife = '{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.SMALL_BLADE }), part = "Torso_Upper" }'
        self.assertEqual(self.made(knife, 'seq({ 0.1 })')[0][0][:3], ('Torso_Upper', 'deep', True))
        self.assertEqual(self.made(knife, 'seq({ 0.5, 0.2 })')[0][0][:3], ('Torso_Upper', 'laceration', True))
        self.assertEqual(self.made(knife, 'seq({ 0.5, 0.5 })')[0][0][:3], ('Torso_Upper', 'scratch', False))
        # Partie inconnue du moteur : tirée de Hand_L à Foot_R.
        hit = '{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.LONG_BLADE }), part = "Tail" }'
        self.assertEqual(self.made(hit, 'seq({ 0.999 })')[0][0][0], 'Foot_R')

    def test_blunt_laceration_one_in_four_else_scratch(self):
        bat = '{ attacker = PLAYER(), weapon = WEAPON({ WeaponCategory.BLUNT }), part = "Head" }'
        self.assertEqual(self.made(bat, 'seq({ 0.2 })')[0][0][:3], ('Head', 'laceration', True))
        self.assertEqual(self.made(bat, 'seq({ 0.3 })')[0][0][:3], ('Head', 'scratch', False))

    def test_bullet_is_a_lodged_bullet_that_bleeds(self):
        made, src = self.made('{ attacker = PLAYER(), weapon = WEAPON({}, true), part = "Torso_Lower" }',
                              'seq({ 0.5 })')
        self.assertEqual(src, 'firearm')
        self.assertEqual(made[0][:3], ('Torso_Lower', 'bullet', True))
        self.assertIsNone(made[0][3])                                    # ne guérit pas seule
        self.assertIs(self.ev('ADDED[1].foreign'), True)

    # ------------------------------------------------------------------ feu et verre
    def test_fire_burns_one_part_for_50_to_100(self):
        made, src = self.made('{ source = "fire" }', 'seq({ 0.5 })')
        self.assertEqual(src, 'fire')
        self.assertEqual(made, [('Head', 'burn', False, 75)])            # Hand_L..Foot_R index 1 + 8 ; 50 + 0.5 x 50
        self.run_lua('C2 = { rnd = seq({ 0.0 }), severity = 3 }; L2 = {}; '
                     f'{W}.fromHit(L2, {{ source = "fire" }}, C2)')
        self.assertEqual(self.ev('L2[1].time'), 75)                      # 50 x 1,5 (InjurySeverity 3)

    def test_glass_rule_one_in_two_hands_and_forearms_one_in_seven_shards(self):
        glass = '{ source = "glass" }'
        self.assertEqual(self.made(glass, 'seq({ 0.6 })'), ([], 'glass'))                 # 1 fois sur 2 : rien
        self.assertEqual(self.made(glass, 'seq({ 0.4, 0.99, 0.1 })')[0][0][:3], ('ForeArm_R', 'glass', True))
        made = self.made(glass, 'seq({ 0.4, 0.0, 0.5, 0.5 })')[0]
        self.assertEqual(made[0][:3], ('Hand_L', 'scratch', True))                        # griffure de fenêtre : saigne
        self.assertEqual(made[0][3], 16)                                                  # 12 + 0.5 x 8
        self.assertEqual(self.made('{ source = "glass", risk = false }', 'seq({ 0.9, 0.5, 0.5 })')[0][0][1],
                         'scratch')                                                       # risque déjà décidé
        # Répartition sur 14000 passages (suite reproductible).
        self.run_lua(f'C = {{ rnd = lcg(11) }}; N, SH, SC, PARTS = 0, 0, 0, {{}}; '
                     f'for i = 1, 14000 do local L = {{}} {W}.fromHit(L, {{ source = "glass" }}, C) '
                     'if #L > 0 then N = N + 1 PARTS[L[1].part] = true '
                     'if L[1].kind == "glass" then SH = SH + 1 else SC = SC + 1 end end end')
        n, shards = self.ev('N'), self.ev('SH')
        self.assertAlmostEqual(n / 14000, 0.5, delta=0.02)
        self.assertAlmostEqual(shards / n, 1 / 7, delta=0.02)
        self.assertEqual(sorted(p for p in PARTS if self.ev(f'PARTS["{p}"]')),
                         sorted(['Hand_L', 'Hand_R', 'ForeArm_L', 'ForeArm_R']))

    # ------------------------------------------------------------------ contexte du jeu
    def test_context_reads_day_length_and_injury_severity(self):
        c = self.ev('LivingKnox.WoundContext.current()')
        self.assertEqual((c.minutesPerDay, c.severity, c.woundInfectionFactor), (90, 2, 0))
        self.assertEqual(c.rnd(), 0.25)                                   # ZombRand(1e6) / 1e6
        self.run_lua('OPTIONS.InjurySeverity = 3; OPTIONS.WoundInfectionFactor = 0.5; MPD = 60')
        c = self.ev('LivingKnox.WoundContext.current()')
        self.assertEqual((c.minutesPerDay, c.severity, c.woundInfectionFactor), (60, 3, 0.5))
        self.run_lua('OPTIONS.InjurySeverity = 9')
        self.assertEqual(self.ev('LivingKnox.WoundContext.current().severity'), 2)
        self.run_lua('LivingKnox.WoundContext.rnd = function() return 0.125 end')
        self.assertEqual(self.ev('LivingKnox.WoundContext.current().rnd()'), 0.125)

    def test_context_reads_the_virus_options_clock_and_test_delay(self):
        # LK21-T04 : options ZombieLore.Transmission et ZombieLore.Mortality (SandboxOptions.java:1908-1909), âge du
        # monde, délai imposé des essais (Config.INFECTION.DELAY_HOURS).
        c = self.ev('LivingKnox.WoundContext.current()')
        self.assertEqual((c.transmission, c.mortality, c.worldHours, c.virusDelay), (None, None, 30.5, None))
        self.run_lua('OPTIONS["ZombieLore.Transmission"] = 4; OPTIONS["ZombieLore.Mortality"] = 2; AGE = 100; '
                     'LivingKnox.Config.INFECTION.DELAY_HOURS = 0.25')
        c = self.ev('LivingKnox.WoundContext.current()')
        self.assertEqual((c.transmission, c.mortality, c.worldHours, c.virusDelay), (4, 2, 100, 0.25))

    def test_add_time_override_is_checked(self):
        self.assertEqual(self.ev(f'(select(2, {W}.add({{}}, "Hand_L", "scratch", {{ rnd = seq({{ 0.5 }}) }}, '
                                 '{ time = { 5, 2 } })))'), 'bad time range')


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in MODULES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')

    def test_engine_names_no_source(self):
        engine = re.sub(r'--[^\n]*', '', (LK_SERVER / 'LivingKnox' / 'LK_WoundSources.lua').read_text(encoding='utf-8'))
        health = re.sub(r'--[^\n]*', '', (LK_SERVER / 'LivingKnox' / 'LK_Health.lua').read_text(encoding='utf-8'))
        for sid in SOURCES:
            self.assertIsNone(re.search(rf'"{sid}"', engine), sid)
        self.assertIsNone(re.search(r'source\s*==', health))
        self.assertTrue('Wounds.fromHit' in health, 'LK_Health must create wounds through the source registry')


if __name__ == '__main__':
    unittest.main()
