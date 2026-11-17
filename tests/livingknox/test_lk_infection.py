"""Tests hors jeu du virus de Knox chez les PNJ Living Knox (LK21-T04, ADR adr-blessures-soins.md D04) :
shared/LivingKnox/LK_Virus.lua (règles pures : transmission, délai, relevé, forme), server/LivingKnox/LK_Infection.lua
(adaptateur : échéance, mort, relevé en zombie ordinaire, journal, membre hors écran) et la source « zombie »
(server/LivingKnox/Wounds/LK_WoundSource_Zombie.lua).

    python tests/livingknox/test_lk_infection.py

Règles vanilla vérifiées (Java décompilé 42.22, `J/` = E:/pz-source-42.22/java/zombie/) :
- options `ZombieLore.Transmission` 1 sang et salive, 2 salive seule, 3 tout le monde est infecté, 4 aucune
  (`J/SandboxOptions.java:1908`, traductions `Sandbox_ZTransmission_option1..4`) et `ZombieLore.Mortality` 1 à 7
  (`:1909`, défaut 5) ;
- morsure : virus sauf transmission 4 (`J/characters/BodyDamage/BodyPart.java:616-619`) ; griffure 7 % et coupure 25 %
  d'un zombie (`generateZombieInfection`, `:701`, `:744`, `:705-717`), jamais en transmission 2 ou 4 ; mortalité 7 :
  infection fausse, aucune mort (`:620-623`, `:713-716`) ;
- délai tiré par `BodyDamage.pickMortalityDuration` (`J/characters/BodyDamage/BodyDamage.java:1789-1807`, heures) :
  1 = 0, 2 = 0-30 s, 3 = 0,5-1 min, 4 = 3-12 h, 5 = 2-3 jours, 6 = 1-2 semaines, 7 = jamais ; mort à l'échéance
  (`:2018-2025`) ;
- partie porteuse du virus : aucun tirage d'infection de plaie (`BodyPart.java:221`), niveau d'infection +2e-4 par
  tick (`:282-283`) ;
- mort puis relevé : `IsoGameCharacter.shouldBecomeZombieAfterDeath` (`J/characters/IsoGameCharacter.java:10523-10540` :
  transmission 3 toujours, 1 et 2 si infecté, 4 jamais), `IsoPlayer.onDied` -> `IsoDeadBody.reanimateLater`
  (`J/characters/IsoPlayer.java:7791-7794`, `J/iso/objects/IsoDeadBody.java:1756-1758`), relevé par
  `IsoDeadBody.update` (`:1764-1775`) puis `reanimate` (`:1834-1946`, ModData copiées, joueur réanimé).
Doublures du banc (elles NE PROUVENT PAS l'API réelle) : options (`getSandboxOptions`), `IsoDeadBody.reanimateLater`
et `getReanimateTime`, relevé des cadavres dus (RISE_DUE).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from harness import lua_src  # noqa: E402
from test_lk_bodies import DEV_LUA, lua_list  # noqa: E402
from test_lk_death import DEATH_DOUBLES  # noqa: E402
from test_lk_health import HEALTH, HEALTH_DOUBLES  # noqa: E402
from test_lk_materialize import CREW, MatBase  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
LK_LUA = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'
LK_SHARED = LK_LUA / 'shared'
LK_SERVER = LK_LUA / 'server'
KIND_DIR = LK_SHARED / 'LivingKnox' / 'Wounds'
SOURCE_DIR = LK_SERVER / 'LivingKnox' / 'Wounds'
VIRUS = LK_SHARED / 'LivingKnox' / 'LK_Virus.lua'
INFECTION = 'server/LivingKnox/LK_Infection.lua'
JOURNAL = 'server/LivingKnox/LK_Journal.lua'
W, V = 'LivingKnox.Wounds', 'LivingKnox.Virus'
TPM = 180   # ticks par minute de jeu (journée de 90 minutes)

PURE_DOUBLES = r'''
function instanceof(o, name) return type(o) == "table" and o.classes ~= nil and o.classes[name] == true end
-- class(nom) : doublure rattachee a sa classe Java (methodes controlees par test_doubles_api).
local function class(name) local c = { __javaName = name } c.__index = c return c end
local Zed = class("IsoZombie")
function Zed:isCrawling() return false end
function ZOMBIE() return setmetatable({ classes = { IsoZombie = true } }, Zed) end
function seq(t) local i = 0 return function() i = i % #t + 1 return t[i] end end
'''


class VirusTests(unittest.TestCase):
    """Règles pures (LK_Virus) et transmission par la source « zombie » (registre des sources)."""

    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;{LK_SERVER.as_posix()}/?.lua;]]; '
                        'package.cpath = ""')
        self.rt.execute(PURE_DOUBLES)
        for name in ('LK_Wounds', 'LK_WoundsForm', 'LK_Virus'):
            self.rt.execute(f'require "LivingKnox/{name}"')
        for path in sorted(KIND_DIR.glob('*.lua')):
            self.rt.execute(f'require "LivingKnox/Wounds/{path.stem}"')
        self.rt.execute('require "LivingKnox/LK_WoundSources"')
        for path in sorted(SOURCE_DIR.glob('*.lua')):
            self.rt.execute(path.read_text(encoding='utf-8'))

    def ev(self, code):
        return self.rt.execute('return ' + code)

    def run_lua(self, code):
        return self.rt.execute(code)

    def bite(self, transmission=1, mortality=5, issue='bite', rnd='seq({ 0.5 })', hours=100, extra=''):
        """Coup de zombie (issue imposée) sur une liste vide L ; ctx C (options, heure du monde, tirages rnd)."""
        self.run_lua(f'L = {{}}; C = {{ rnd = {rnd}, transmission = {transmission}, mortality = {mortality}, '
                     f'worldHours = {hours}{extra} }}; '
                     f'ADDED = {W}.fromHit(L, {{ attacker = ZOMBIE(), issue = "{issue}" }}, C)')

    def virus(self):
        return self.ev('L.virus')

    # ------------------------------------------------------------------ transmission
    def test_bite_transmits_unless_the_option_says_none(self):
        for transmission in (1, 2, 3):
            with self.subTest(transmission=transmission):
                self.bite(transmission)
                self.assertIsNotNone(self.virus())
                self.assertIs(self.ev('ADDED[1].virus'), True)           # partie porteuse (BodyPart.isInfected)
                self.assertIs(self.ev('ADDED[1].infected'), True)        # infection de plaie de la morsure (:608)
        self.bite(4)                                                     # aucune transmission (:616-619)
        self.assertIsNone(self.virus())
        self.assertIsNone(self.ev('ADDED[1].virus'))
        self.assertIs(self.ev('ADDED[1].infected'), True)
        self.bite(1, mortality=7)                                        # mortalité « jamais » : infection fausse
        self.assertIsNone(self.virus())

    def test_scratch_and_laceration_chances_blood_route_only(self):
        # Griffure 7 % : tirage 0,06 (< 7 %) transmet, 0,5 non (generateZombieInfection :705-717).
        self.bite(issue='scratch', rnd='seq({ 0.06 })')
        self.assertIsNotNone(self.virus())
        self.bite(issue='scratch', rnd='seq({ 0.5 })')
        self.assertIsNone(self.virus())
        self.bite(issue='laceration', rnd='seq({ 0.24 })')               # coupure 25 %
        self.assertIsNotNone(self.virus())
        self.bite(issue='laceration', rnd='seq({ 0.26 })')
        self.assertIsNone(self.virus())
        for transmission in (2, 4):                                      # salive seule, ou aucune
            with self.subTest(transmission=transmission):
                self.bite(transmission, issue='scratch', rnd='seq({ 0 })')
                self.assertIsNone(self.virus())
        self.assertEqual(self.ev(f'{W}.kind("bite").virusRoute'), 'saliva')
        self.assertEqual(self.ev(f'{W}.kind("scratch").virusRoute'), 'blood')
        self.assertEqual(self.ev(f'{W}.kind("laceration").virusRoute'), 'blood')

    def test_other_sources_never_transmit(self):
        self.run_lua(f'L = {{}}; C = {{ rnd = seq({{ 0 }}), transmission = 1, mortality = 5, worldHours = 1 }}; '
                     f'{W}.fromHit(L, {{ source = "glass" }}, C); {W}.fromHit(L, {{ source = "fire" }}, C)')
        self.assertGreater(self.ev('#L'), 0)
        self.assertIsNone(self.virus())

    def test_second_bite_keeps_the_first_due_hour(self):
        self.bite(hours=10)
        due = self.ev('L.virus.due')
        self.run_lua(f'C.worldHours = 20; {W}.fromHit(L, {{ attacker = ZOMBIE(), issue = "bite" }}, C)')
        self.assertEqual(self.ev('L.virus.due'), due)
        self.assertEqual(self.ev('L.virus.since'), 10)

    # ------------------------------------------------------------------ délai (pickMortalityDuration)
    def test_delay_drawn_in_the_vanilla_table(self):
        table = {1: (0, 0), 2: (0, 30 / 3600), 3: (0.5 / 60, 1 / 60), 4: (3, 12), 5: (48, 72), 6: (168, 336)}
        for mortality, (lo, hi) in table.items():
            for r in (0, 0.5, 0.999):
                with self.subTest(mortality=mortality, rnd=r):
                    self.bite(mortality=mortality, rnd=f'seq({{ {r} }})', hours=100)
                    self.assertEqual(self.ev('L.virus.since'), 100)
                    self.assertAlmostEqual(self.ev('L.virus.due') - 100, lo + (hi - lo) * r, places=9)
        self.assertIsNone(self.ev(f'{V}.contract({{ rnd = seq({{ 0.5 }}), mortality = 7, worldHours = 1 }})'))
        # Réglage de configuration pour les essais (délai réduit) : remplace le tirage.
        self.bite(mortality=6, extra=', virusDelay = 0.25', hours=3)
        self.assertAlmostEqual(self.ev('L.virus.due'), 3.25)
        # Horloge inconnue : aucune échéance inventée.
        self.assertIsNone(self.ev(f'{V}.contract({{ rnd = seq({{ 0.5 }}), mortality = 5 }})'))
        self.assertIs(self.ev(f'{V}.isDue({{ since = 1, due = 2 }}, 1.99)'), False)
        self.assertIs(self.ev(f'{V}.isDue({{ since = 1, due = 2 }}, 2)'), True)
        self.assertIs(self.ev(f'{V}.isDue(nil, 99)'), False)

    def test_who_rises_after_death(self):
        cases = {(1, True): True, (1, False): False, (2, True): True, (2, False): False,
                 (3, False): True, (3, True): True, (4, True): False, (4, False): False}
        for (transmission, infected), expected in cases.items():
            with self.subTest(transmission=transmission, infected=infected):
                self.assertIs(self.ev(f'{V}.rises({str(infected).lower()}, {{ transmission = {transmission} }})'),
                              expected)
        self.assertIs(self.ev(f'{V}.rises(true, {{}})'), True)            # défaut du vanilla : 1

    # ------------------------------------------------------------------ plaie porteuse du virus
    def test_carrier_wound_never_rolls_and_worsens_faster(self):
        self.bite(issue='scratch', rnd='seq({ 0.06 })')
        self.assertIs(self.ev('L[1].virus'), True)
        self.assertEqual(self.ev(f'{W}.infectionChance(L[1], C)'), 0)    # porte :221
        self.run_lua(f'C.rnd = function() return 0 end; {W}.advance(L, 10, C)')
        self.assertFalse(self.ev('L[1].infected'))
        self.bite()
        self.run_lua(f'{W}.advance(L, 60, C)')
        self.assertAlmostEqual(self.ev('L[1].level'), 2e-4 * 60 * TPM, places=9)   # :282-283

    # ------------------------------------------------------------------ forme sauvegardée
    def test_virus_saved_with_the_wounds_and_validated(self):
        self.bite(hours=12.5, mortality=4, rnd='seq({ 0.5 })')
        self.run_lua(f'{W}.add(L, "Hand_L", "burn", C)')                 # seconde plaie, sans virus
        text = self.ev(f'{W}.pack(L)')
        # En-tête « virus:<début>:<échéance>:<plaies porteuses> » ; le texte de chaque plaie est inchangé.
        self.assertTrue(text.startswith('virus:12.5:20:1|bite:'), text)
        self.assertEqual(text.split('|', 1)[1], self.ev(f'{W}.pack({{ L[1], L[2] }})'))
        back = self.ev(f'{W}.unpack("{text}")')
        self.assertEqual((back.virus.since, back.virus.due), (12.5, 20))
        self.assertIs(back[1].virus, True)
        self.assertIsNone(back[2].virus)
        self.assertEqual(self.ev(f'{W}.pack({W}.unpack({W}.pack(L)))'), text)
        # Virus sans plaie (morsure guérie) : la forme garde le virus seul.
        self.run_lua('NOW = { virus = { since = 1, due = 2 } }')
        self.assertEqual(self.ev(f'{W}.pack(NOW)'), 'virus:1:2:|')
        self.assertEqual(self.ev(f'#{W}.unpack("virus:1:2:|")'), 0)
        self.assertEqual(self.ev(f'{W}.unpack("virus:1:2:|").virus.due'), 2)
        for bad in ('virus:2:1:|', 'virus:x:2:|', 'virus:1:|', 'virus:-1:2:|', 'virus:1:2:', 'virus:1:2:1|',
                    'virus:1:1e999:|', 'virus:1:2:0|', 'virus:1:2:x|', 'virus:1:2:|' + text.split('|', 1)[1] + '|'):
            with self.subTest(bad=bad):
                self.assertIsNone(self.ev(f'({W}.unpack("{bad}"))'))
        self.assertFalse(self.ev(f'({W}.valid({{ virus = {{ since = 3, due = 1 }} }}))'))

    def test_virus_module_is_pure(self):
        code = '\n'.join(line.split('--', 1)[0] for line in VIRUS.read_text(encoding='utf-8').splitlines())
        game = re.compile(r'\b(getPlayer|getGameTime|getSandboxOptions|SandboxVars|ZombRand\w*|isServer|isClient|'
                          r'getCell|getWorld|Events)\b')
        self.assertIsNone(game.search(code))
        self.assertNotIn('next(', code)
        self.assertTrue(code.isascii())
        for kind in ('"bite"', '"scratch"', '"laceration"'):
            self.assertNotIn(kind, code)                                  # aucun type de plaie nommé


INFECTION_DOUBLES = r'''
local H = HARNESS
local Body = H.classes.IsoDeadBody
-- Options sandbox (SandboxOptions.getOptionByName(...):getValue()) ; absentes : défaut du jeu.
OPTIONS = {}
getSandboxOptions = function()
    return { getOptionByName = function(_, name)
        local v = OPTIONS[name]
        if v == nil then return nil end
        return { getValue = function() return v end }
    end }
end
-- IsoDeadBody.reanimateLater : heure du relevé = âge du monde + délai de l'option Reanimate (IsoDeadBody.java:1718-1758).
REANIMATE_DELAY = 0.01
function Body:reanimateLater() self.reanimateTime = getGameTime():getWorldAgeHours() + REANIMATE_DELAY end
function Body:getReanimateTime() return self.reanimateTime or -1 end
-- IsoDeadBody.update hors client : cadavre dont l'heure est venue relevé (IsoDeadBody.java:1764-1775).
function RISE_DUE()
    local out = {}
    for _, b in ipairs(CORPSES) do
        local t = b.reanimateTime or -1
        if b.square ~= nil and t > 0 and t <= getGameTime():getWorldAgeHours() then
            b.reanimateTime = -1
            out[#out + 1] = b:reanimate()
        end
    end
    return out
end
-- Faits publiés.
MEMBER_DIED, NPC_DIED, RISEN = {}, {}, {}
LivingKnox.listen("memberDied", "test.infection", function(i) MEMBER_DIED[#MEMBER_DIED + 1] = i end)
LivingKnox.listen("npcDied", "test.infection", function(i) NPC_DIED[#NPC_DIED + 1] = i end)
LivingKnox.listen("npcRisen", "test.infection", function(i) RISEN[#RISEN + 1] = i end)
function TAGGED_ALIVE(id)
    local n = 0
    for _, zb in ipairs(H.zombieList.items) do
        if not zb:isDead() and zb:hasModData() and LivingKnox.Identity.readTag(zb:getModData()) == id then n = n + 1 end
    end
    return n
end
function LOG_KINDS(gid, kind)
    local n = 0
    for _, e in ipairs(LivingKnox.Groups.get(gid).log or {}) do if e.kind == kind then n = n + 1 end end
    return n
end
function STORY_KINDS(gid, kind)
    local n = 0
    local j = LivingKnox.Groups.get(gid).journal
    for _, e in ipairs(j and j.e or {}) do if e.kind == kind then n = n + 1 end end
    return n
end
'''


class InfectionBase(MatBase):
    """Groupe de trois membres matérialisés près du joueur (solo) ; santé, mort et cadavres, virus, journal."""
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', HEALTH_DOUBLES)
        h.load('solo', HEALTH)
        h.load('solo', DEATH_DOUBLES)
        h.load('solo', JOURNAL)
        h.load('solo', INFECTION)
        h.load('solo', INFECTION_DOUBLES)
        return h

    def setUp(self):
        super().setUp()
        self.gid = self.mk_group(crew=CREW[:3])
        self.h.move_player('A', 100, 100)
        self.passes(3)
        self.assertEqual(self.bodies(self.gid), ['m-1', 'm-2', 'm-3'])
        self.id = self.member(self.gid, 'm-2', 'npc')
        self.run_lua('LivingKnox.WoundContext.rnd = function() return 0.5 end')
        self.h.advance(1)                                                   # premier passage : repère des minutes

    def tearDown(self):
        self.run_lua('LivingKnox.Config.INFECTION.DELAY_HOURS = nil')
        super().tearDown()

    def bite(self, npc=None):
        npc = npc or self.id
        self.run_lua(f'VZ = NEW_ZOMBIE(103.5, 102.5, 0, false); '
                     f'LivingKnox.Health.applyHit("{npc}", LivingKnox.Bodies.bound["{npc}"], 0.1, "zombie bite", VZ, '
                     'nil, { issue = "bite" })')

    def state(self, field):
        return self.ev(f'LivingKnox.Store.data().npcs["{self.id}"] and LivingKnox.Store.data().npcs["{self.id}"].{field}')

    def hours(self):
        return self.ev('getGameTime():getWorldAgeHours()')


class EmbodiedInfectionTests(InfectionBase):
    def test_bite_infects_the_npc_who_knows_it_and_the_journal_notes_it(self):
        self.run_lua('OPTIONS["ZombieLore.Mortality"] = 4')               # 3-12 h, tirage 0,5 : 7,5 h
        start = self.hours()
        self.bite()
        h = self.ev(f'LivingKnox.Health.get("{self.id}")')
        self.assertIs(h.virus, True)                                         # le PNJ mordu le sait
        self.assertEqual(h.wounds[1].kind, 'bite')
        v = self.ev(f'LivingKnox.Infection.state("{self.id}")')
        self.assertAlmostEqual(v.since, start, places=5)
        self.assertAlmostEqual(v.due - v.since, 7.5, places=5)
        self.assertTrue(self.state('wounds').startswith('virus:'))
        self.assertEqual(self.ev(f'LOG_KINDS("{self.gid}", "infected")'), 1)
        self.assertEqual(self.ev(f'STORY_KINDS("{self.gid}", "infected")'), 1)
        self.assertTrue(any(f'npc {self.id} infected by the Knox virus' in line for line in self.lk()), self.lk())
        self.bite()                                                          # seconde morsure : rien de nouveau
        self.assertEqual(self.ev(f'LOG_KINDS("{self.gid}", "infected")'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_transmission_option_is_respected(self):
        self.run_lua('OPTIONS["ZombieLore.Transmission"] = 4')
        self.bite()
        self.assertIs(self.ev(f'LivingKnox.Health.get("{self.id}").virus'), False)
        self.assertIs(self.ev(f'LivingKnox.Health.get("{self.id}").wounds[1].infected'), True)   # plaie, pas virus
        self.assertIsNone(self.ev(f'LivingKnox.Infection.state("{self.id}")'))
        self.assertEqual(self.ev(f'LOG_KINDS("{self.gid}", "infected")'), 0)
        # Mort par une autre cause : aucun relevé (transmission 4, shouldBecomeZombieAfterDeath).
        self.ev(f'LivingKnox.Health.kill("{self.id}")')
        self.h.tick(3)
        self.assertIsNone(self.state('rises'))
        self.assertEqual(self.ev('LAST_CORPSE():getReanimateTime()'), -1)

    def test_death_at_due_then_rises_as_an_ordinary_zombie_and_the_group_mourns(self):
        self.run_lua('LivingKnox.Config.INFECTION.DELAY_HOURS = 0.5')     # délai réduit des essais
        self.bite()
        self.h.advance(28)
        self.assertEqual(self.state('state'), 'embodied')
        self.h.advance(3)
        self.assertEqual(self.state('state'), 'dead')
        self.assertEqual(self.state('death').cause, 'infection')
        self.assertEqual(self.ev('#NPC_DIED'), 1)
        self.assertEqual(self.ev('NPC_DIED[1].cause'), 'infection')
        # Le groupe le pleure : fait memberDied (observation group_death), membre mort une fois, journal.
        self.assertEqual(self.ev('#MEMBER_DIED'), 1)
        self.assertEqual((self.ev('MEMBER_DIED[1].member'), self.ev('MEMBER_DIED[1].offscreen')), ('m-2', False))
        self.assertIs(self.member(self.gid, 'm-2', 'alive'), False)
        self.assertEqual(self.ev(f'STORY_KINDS("{self.gid}", "died")'), 1)
        # Cadavre : relevé du vanilla programmé (reanimateLater), puis relevé par le moteur.
        self.h.tick(5)
        self.assertGreater(self.ev('LAST_CORPSE():getReanimateTime()'), 0)
        self.assertIs(self.state('rises'), True)
        self.h.advance(1)
        risen = self.ev('RISE_DUE()[1]')
        self.assertIsNotNone(risen)
        self.ev('LivingKnox.Bodies.scanAll()')
        # Zombie ordinaire : debout, sans étiquette, hors du registre des PNJ ; jamais remis à terre.
        self.assertIs(risen.isDead(risen), False)
        self.assertEqual(self.ev(f'TAGGED_ALIVE("{self.id}")'), 0)
        self.assertIsNone(self.ev(f'LivingKnox.Store.data().npcs["{self.id}"]'))
        self.assertEqual(self.ev('LivingKnox.Bodies.stats.laidDown'), 0)
        self.assertEqual((self.ev('#RISEN'), self.ev('RISEN[1].npc')), (1, self.id))
        self.assertEqual(self.ev('LivingKnox.Infection.stats.risen'), 1)
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(risen.isDead(risen), False)
        self.assertEqual(self.h.errors('solo'), [])

    def test_infected_npc_killed_before_due_still_rises(self):
        self.bite()
        self.ev(f'LivingKnox.Health.kill("{self.id}")')
        self.assertEqual(self.state('death').cause, 'unknown')
        self.h.tick(5)
        self.assertIs(self.state('rises'), True)
        self.assertGreater(self.ev('LAST_CORPSE():getReanimateTime()'), 0)

    def test_everyone_infected_option_raises_any_dead_npc(self):
        self.run_lua('OPTIONS["ZombieLore.Transmission"] = 3')
        self.ev(f'LivingKnox.Health.kill("{self.id}")')
        self.h.tick(5)
        self.assertIs(self.state('rises'), True)
        self.assertGreater(self.ev('LAST_CORPSE():getReanimateTime()'), 0)

    def test_infection_saved_with_the_wounds_and_read_back(self):
        self.bite()
        text = self.state('wounds')
        due = self.ev(f'LivingKnox.Infection.state("{self.id}").due')
        self.assertIsNotNone(self.ev('(LivingKnox.Identity.validate(LivingKnox.Store.data()))'))
        self.run_lua('LivingKnox.Store.save()')
        self.init()                                                          # relecture du fichier du registre
        self.run_lua('LivingKnox.Health.woundCache = {}')
        self.assertEqual(self.state('wounds'), text)
        self.assertAlmostEqual(self.ev(f'LivingKnox.Infection.state("{self.id}").due'), due, places=5)
        # Forme fausse : registre refusé à la relecture.
        self.run_lua(f'LivingKnox.Store.data().npcs["{self.id}"].wounds = "virus:5:1:|"')
        res = lua_list(self.ev('{ LivingKnox.Identity.validate(LivingKnox.Store.data()) }'))
        self.assertIsNone(res[0])
        self.assertIn('bad wounds', res[1])


class OffscreenInfectionTests(InfectionBase):
    def offscreen(self, mid, since, due):
        self.update(self.gid, f'g.members["{mid}"].wounds = "virus:{since}:{due}:|"')

    def test_offscreen_member_dies_at_due_without_rising_and_its_death_is_noted(self):
        self.away()
        self.wait(65)
        self.assertEqual(self.bodies(self.gid), [])
        hour = int(self.hours()) + 1
        self.offscreen('m-3', hour - 2, hour + 0.5)
        self.run_lua(f'local G = LivingKnox.Groups local g = G.state.data.groups["{self.gid}"] '
                     f'LivingKnox.Simulation.simulateHour(g, "{self.gid}", {hour}, 1)')
        self.assertIs(self.member(self.gid, 'm-3', 'alive'), True)
        self.assertEqual(self.member(self.gid, 'm-3', 'wounds'), f'virus:{hour - 2}:{hour + 0.5}:|')
        self.run_lua(f'local G = LivingKnox.Groups local g = G.state.data.groups["{self.gid}"] '
                     f'LivingKnox.Simulation.simulateHour(g, "{self.gid}", {hour + 1}, 1)')
        self.assertIs(self.member(self.gid, 'm-3', 'alive'), False)
        self.assertIsNone(self.member(self.gid, 'm-3', 'wounds'))
        self.assertEqual(self.ev(f'LOG_KINDS("{self.gid}", "died")'), 1)
        self.assertEqual(self.ev('#MEMBER_DIED'), 1)
        self.assertIs(self.ev('MEMBER_DIED[1].offscreen'), True)
        self.assertEqual(self.ev('#RISEN'), 0)                              # aucun corps : aucun relevé
        self.assertTrue(any(f'group {self.gid} member m-3 died of the Knox virus offscreen' in line
                            for line in self.lk()), self.lk())

    def test_offscreen_virus_survives_a_wound_pass(self):
        self.away()
        self.wait(65)
        self.offscreen('m-3', 0, 1e6)
        self.run_lua(f'local m = LivingKnox.Groups.state.data.groups["{self.gid}"].members["m-3"] '
                     'local Mh = LivingKnox.MemberHealth '
                     'local ctx = Mh.context(function() return 0.5 end) ctx.worldHours = 10 '
                     'OK = Mh.pass(m, 60, ctx)')
        self.assertIs(self.ev('OK'), True)
        self.assertEqual(self.member(self.gid, 'm-3', 'wounds'), 'virus:0:1000000:|')


SUITE = 'shared/RST/suites/RST_LKWounds.lua'


class SuiteTests(InfectionBase):
    def test_suite_lk_wounds_passes_on_the_doubles(self):
        # Moteur : relevé des cadavres dus à chaque image (IsoDeadBody.update) ; corps debout ; une minute de jeu toutes
        # les 20 images (EveryOneMinute : échéance du virus).
        self.run_lua('function HARNESS.classes.IsoDeadBody:reanimateNow() '
                     'self.reanimateTime = getGameTime():getWorldAgeHours() end '
                     'REANIMATE_DELAY = 0.2 '      # option Reanimate lointaine : relevé avancé par la suite
                     'Events.OnTick.Add(function() RISE_DUE() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.wounds", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.wounds')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.wounds", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(6000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(50)
            if i % 20 == 19:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKW] measure')]
        self.assertTrue(any('risen: facts 1, risen +1, laid down +0' in line for line in measures), measures)
        self.assertIsNone(self.ev('LivingKnox.Config.INFECTION.DELAY_HOURS'))      # réglage rendu

    def test_suite_skips_when_the_bite_does_not_kill(self):
        self.run_lua('OPTIONS["ZombieLore.Mortality"] = 7')
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.wounds", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(200):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(50)
        report = self.h.eval('solo', 'RST.last()')
        self.assertEqual([r.status for r in lua_list(report.results)], ['SKIP'])


class SourceRulesTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = (DEV_LUA / SUITE).read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def test_kahlua_safe_new_files(self):
        for path in (VIRUS, lua_src(INFECTION)):
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--[^\n]*', '', text)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'(?<![.:])\bunpack\b'):
                self.assertIsNone(re.search(pattern, code), f'{path.name}: {pattern}')

    def test_infection_module_names_no_wound_kind(self):
        code = '\n'.join(line.split('--', 1)[0] for line in lua_src(INFECTION).read_text(encoding='utf-8').splitlines())
        for kind in ('"bite"', '"scratch"', '"laceration"'):
            self.assertNotIn(kind, code)
        self.assertIn('if isClient() then return end', code)


if __name__ == '__main__':
    unittest.main()
