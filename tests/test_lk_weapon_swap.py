"""Tests hors jeu de LK07-T08 : arme d'un PNJ vivant remplacée par un mod d'armes, rien de perdu.
LK_Equipment.adoptForeign (arme réellement accrochée relue et adoptée), LK_Ammo.convert (munitions reportées),
LK_Combat.step (ordre renouvelé quand l'arme change), LK_Loot.onDeath (adoption avant le butin).

    python RadioSurvivor/tests/test_lk_weapon_swap.py

Banc du butin (test_lk_loot.LootBase : corps, santé, mort, armes, munitions) complété de la mêlée et du tir
(test_lk_combat), et de SWAP_DOUBLES ci-dessous. Les doublures reproduisent le Java 42.21.0 relevé (objets accrochés
IsoGameCharacter.java:3178-3206, ModData d'objet InventoryItem.java:414-423) et le COMPORTEMENT relevé en lecture
seule d'un mod d'armes actif lors du constat du 2026-10-12 (aucun code repris) : une fois par zombie, à une mise à jour,
chaque objet accroché dont le type a un remplaçant est remplacé AU MÊME EMPLACEMENT par un objet neuf d'un autre type
d'arme (autre emplacement d'accroche, autres munitions), envoyé aux clients sur un serveur (sendAttachedItem) ; les
munitions restées dans l'inventaire d'un zombie vivant ne sont pas remplacées. Elles NE PROUVENT PAS l'API réelle.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_loot import LootBase  # noqa: E402
from test_lk_combat import (COMBAT_DOUBLES, COMBAT, COMBAT_CLIENT, AMMO,  # noqa: E402
                            MultiplayerCombatTests, RangedMultiplayerTests)

EQUIPMENT = 'shared/LivingKnox/LK_Equipment.lua'
SUITE = 'shared/RST/suites/RST_LKWeaponSwap.lua'
PISTOL = 'Base.Pistol'

SWAP_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Item, W = C.InventoryItem, C.HandWeapon
-- Armes d'un mod d'armes (doublures) : autre emplacement, autres cartouches, autre chargeur ou aucun.
ITEMS['Mod.SMG'] = { cls = W, at = 'Rifle', two = true, both = true, ranged = true }
ITEMS['Mod.Revolver'] = { cls = W, at = 'Holster', ranged = true, swing = 'Handgun' }
ITEMS['Mod.Gadget'] = { cls = W, at = 'ModOnlySlot', ranged = true }   -- emplacement inconnu du moteur de PNJ
for _, t in ipairs({ 'Mod.Round9', 'Mod.Mag30', 'Mod.Round38' }) do ITEMS[t] = { cls = Item } end
FIREARMS['Mod.SMG'] = { round = 'Mod.Round9', mag = 'Mod.Mag30', max = 30, per = 1, radius = 80, volume = 40,
    sound = 'SMGShoot', hit = 50, aimMod = 4, minS = 2, maxS = 6 }
FIREARMS['Mod.Revolver'] = { round = 'Mod.Round38', max = 6, per = 1, radius = 100, volume = 30,
    sound = 'RevolverShoot', hit = 50, aimMod = 4, minS = 2, maxS = 6 }
RANGES['Mod.SMG'], RANGES['Mod.Revolver'] = 15, 12
CREATED_TYPES = {}
local prevInstance = instanceItem
instanceItem = function(t)
    local it = prevInstance(t)
    if it ~= nil then CREATED_TYPES[t] = (CREATED_TYPES[t] or 0) + 1 end
    return it
end
-- Remplacement d'un mod d'armes : SWAP.map[type] = type remplaçant ; une fois par zombie, à la première image où
-- SWAP.on est vrai (en jeu : passage différé après OnZombieCreate, ou première mise à jour du zombie), sur la machine
-- qui fait autorité (serveur, solo).
SWAP = { map = {}, on = false, done = {}, n = 0 }
Events.OnTick.Add(function()
    if not SWAP.on or isClient() then return end
    for _, zb in pairs(H.zombies) do
        if not SWAP.done[zb] then
            SWAP.done[zb] = true
            local att = rawget(zb, 'att') or {}
            local locs = {}
            for loc in pairs(att) do locs[#locs + 1] = loc end
            table.sort(locs)
            for _, loc in ipairs(locs) do
                local it = att[loc]
                local t = it and SWAP.map[it:getFullType()]
                if t then
                    local new = instanceItem(t)
                    zb:setAttachedItem(loc, new)
                    if isServer() then sendAttachedItem(zb, loc, new) end
                    SWAP.n = SWAP.n + 1
                    SWAPPED = new
                end
            end
        end
    end
end)
'''


class SwapBase(LootBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, COMBAT_DOUBLES)
            h.load(m, 'RANGES["Base.Shotgun"] = 12')
            h.load(m, COMBAT)
            if m != 'server':
                h.load(m, COMBAT_CLIENT)
            h.load(m, SWAP_DOUBLES)
        return h

    def eq(self, code, m=None):
        return self.ev('LivingKnox.Equipment.' + code, m)

    def am(self, code, m=None):
        return self.ev('LivingKnox.Ammo.' + code, m)

    def c(self, code, m=None):
        return self.ev('LivingKnox.Combat.' + code, m)

    def items(self, t):
        return list(self.run_lua(f'return COUNT_ITEMS(LivingKnox.Bodies.find("lk-1"), "{t}")'))

    def weapon_field(self):
        return self.ev('LivingKnox.Store.data().npcs["lk-1"].weapon')

    def slot(self, loc):
        return self.ev(f'(function() local it = {self.body()}:getAttachedItem("{loc}") '
                       'return it and it:getFullType() end)()')

    def give_pistol_ammo(self, loose=4, mags=1, loaded=9):
        """Pistolet au registre ; réserve et cartouches dans l'arme posées ici (butin marqué comme construit)."""
        self.run_lua(f'{self.body()}:getModData()[LivingKnox.Loot.MD_BUILT] = LivingKnox.Loot.VERSION')
        self.assertIs(self.eq(f'setWeapon("lk-1", "{PISTOL}")'), True)
        self.assertEqual(self.am(f'give("lk-1", "{PISTOL}", {loose}, {mags})'), loose + 15 * mags)
        self.assertEqual(self.am(f'setLoaded({self.body()}, "{PISTOL}", {loaded})'), loaded)

    def swap(self, to, ticks=1):
        """Le mod d'armes remplace l'arme accrochée (une image)."""
        self.run_lua(f'SWAP.map["{PISTOL}"] = "{to}"; SWAP.on = true')
        self.h.tick(ticks)
        self.assertEqual(self.ev('SWAP.n'), 1)
        self.run_lua('SWAPPED_OBJ = SWAPPED')

    def adoption_lines(self):
        return [line for line in self.lk() if 'by another mod, adopted' in line]


class MultiplayerSwapTests(SwapBase):
    ready = MultiplayerCombatTests.ready
    run_ms = RangedMultiplayerTests.run_ms

    def armed(self):
        zid = self.ready('A')
        self.give_pistol_ammo()
        self.h.tick(15)                                   # passage du serveur : pistolet accroché sur sa copie
        self.assertEqual(self.slot('Holster Right'), PISTOL)
        self.assertIs(self.ev(f'{self.body()}:getAttachedItem("Holster Right"):getModData().LKWeapon'), True)
        return zid

    def test_replacement_adopted_moved_to_its_slot_and_ammo_converted(self):
        self.armed()
        pistols = self.ev(f'CREATED_TYPES["{PISTOL}"]')
        self.swap('Mod.SMG')
        self.assertEqual(self.slot('Holster Right'), 'Mod.SMG')    # le mod pose son arme au même emplacement
        self.h.tick(15)
        # Registre : l'arme réellement portée ; même objet, déplacé vers son propre emplacement.
        self.assertEqual(self.weapon_field(), 'Mod.SMG')
        self.assertIs(self.ev(f'rawequal({self.body()}:getAttachedItem("Rifle On Back"), SWAPPED_OBJ)'), True)
        self.assertIsNone(self.slot('Holster Right'))
        self.assertEqual(self.ev('SWAPPED_OBJ:getModData().LKWeapon'), 'lk-1')
        # Munitions : rien de perdu (9 dans l'arme + 4 libres + chargeur de 15 = 28), types de la nouvelle arme.
        self.assertEqual(self.am(f'loaded({self.body()}, "Mod.SMG")'), 9)
        self.assertEqual(self.items('Mod.Mag30'), [1, 15])
        self.assertEqual(self.items('Mod.Round9'), [4, 0])
        self.assertEqual(self.items('Base.9mmClip'), [0, 0])
        self.assertEqual(self.items('Base.Bullets9mm'), [0, 0])
        self.assertEqual(self.am(f'available({self.body()}, "Mod.SMG")'), 28)
        self.assertEqual(self.am(f'available({self.body()}, "{PISTOL}")'), 0)
        # Clients : ancien emplacement vidé, nouvel emplacement envoyé ; table publiée avec l'arme adoptée.
        sent = [(s.l, s.t) for s in lua_list(self.ev('ATTACH_SENT'))]
        self.assertEqual(sent[-3:], [('Holster Right', 'Mod.SMG'), ('Holster Right', None),
                                     ('Rifle On Back', 'Mod.SMG')])
        self.h.pump()
        for cl in ('A', 'B'):
            self.assertEqual(self.h.eval(cl, 'LivingKnox.Equipment.remote.w["lk-1"].t'), 'Mod.SMG')
            self.assertEqual(self.h.eval(cl, 'LivingKnox.Equipment.remote.w["lk-1"].l'), 'Rifle On Back')
        # Stable : aucun pistolet recréé, une seule adoption, une ligne de journal.
        for _ in range(4):
            self.h.tick(15)
        self.assertEqual(self.ev(f'CREATED_TYPES["{PISTOL}"]'), pistols)
        self.assertEqual(self.eq('stats.adopted'), 1)
        self.assertEqual(self.adoption_lines(), [
            '[LivingKnox] INFO npc lk-1 weapon Base.Pistol replaced by Mod.SMG by another mod, adopted (attached, '
            'Rifle On Back): 9 round(s) in the weapon, 4 loose round(s) and 1 magazine(s) converted'], self.lk())
        self.assertEqual(self.h.errors('server'), [])

    def test_npc_fires_with_the_replacing_weapon(self):
        self.armed()
        self.swap('Mod.SMG')
        self.h.tick(15)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.assertEqual(self.c('get("lk-1").m'), 'ranged')
        self.assertEqual(self.c('get("lk-1").t'), 'Mod.SMG')
        self.run_ms(14000)
        shots = self.c('stats.shots')
        self.assertGreaterEqual(shots, 9)                 # 9 dans l'arme, puis rechargement avec le chargeur converti
        self.assertGreaterEqual(self.c('stats.reloads'), 1)
        self.assertEqual(self.c('get("lk-1").t'), 'Mod.SMG')
        self.assertEqual(self.am(f'available({self.body()}, "Mod.SMG")'), 28 - shots)
        self.assertEqual(self.c('stats.outOfAmmo'), 0)
        self.assertEqual(set(lua_list(self.ev('DAMAGES.A or {}'))) - {'Mod.SMG'}, set())
        self.assertEqual({s.name for s in lua_list(self.h.eval('A', 'SHOT_SOUNDS'))}, {'SMGShoot'})
        self.assertEqual(self.weapon_field(), 'Mod.SMG')
        self.assertEqual(self.h.errors('server'), [])

    def test_replacement_during_a_fight_renews_the_order(self):
        self.armed()
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.assertEqual(self.c('get("lk-1").t'), PISTOL)
        self.swap('Mod.SMG', ticks=15)                    # remplacement puis passage du serveur (adoption)
        self.assertEqual(self.weapon_field(), 'Mod.SMG')
        self.run_ms(1000)
        self.assertEqual(self.c('get("lk-1").t'), 'Mod.SMG')
        self.assertEqual(self.c('get("lk-1").m'), 'ranged')
        self.assertEqual(self.c('stats.rearmed'), 1)
        self.assertEqual(self.c('stats.outOfAmmo'), 0)
        self.assertTrue(any('npc lk-1: weapon Base.Pistol changed to Mod.SMG, new order' in line
                            for line in self.lk()), self.lk())

    def test_same_slot_replacement_without_magazine(self):
        self.armed()
        self.swap('Mod.Revolver')
        obj = 'SWAPPED_OBJ'
        self.h.tick(15)
        self.assertEqual(self.weapon_field(), 'Mod.Revolver')
        self.assertIs(self.ev(f'rawequal({self.body()}:getAttachedItem("Holster Right"), {obj})'), True)
        # 9 dans le pistolet : 6 dans le revolver, 3 libres ; chargeur de 15 vidé (gardé), 4 libres échangées.
        self.assertEqual(self.am(f'loaded({self.body()}, "Mod.Revolver")'), 6)
        self.assertEqual(self.items('Mod.Round38'), [3 + 15 + 4, 0])
        self.assertEqual(self.items('Base.9mmClip'), [1, 0])
        self.assertEqual(self.am(f'available({self.body()}, "Mod.Revolver")'), 28)
        self.assertEqual(self.h.errors('server'), [])

    def test_unusable_replacement_puts_the_registry_weapon_back(self):
        self.armed()
        self.swap('Mod.Gadget')
        for _ in range(3):
            self.h.tick(15)
        self.assertEqual(self.weapon_field(), PISTOL)
        self.assertEqual(self.slot('Holster Right'), PISTOL)
        self.assertEqual(self.am(f'loaded({self.body()}, "{PISTOL}")'), 9)
        self.assertEqual(self.am(f'available({self.body()}, "{PISTOL}")'), 28)
        lines = [line for line in self.lk() if 'not usable by an npc' in line]
        self.assertEqual(len(lines), 1, lines)
        self.assertIn('npc lk-1 weapon Base.Pistol replaced by Mod.Gadget, not usable by an npc', lines[0])
        self.assertEqual(self.eq('stats.adopted'), 0)

    def test_own_weapon_of_a_former_registry_entry_never_adopted(self):
        """Corps relu avec l'objet posé par ce module pour une arme précédente (registre changé entre-temps) : l'arme
        du registre l'emporte, l'objet marqué n'est jamais pris pour un remplacement."""
        self.armed()
        self.run_lua('LivingKnox.Store.data().npcs["lk-1"].weapon = "Mod.Revolver"; LivingKnox.Equipment.sent = {}')
        self.h.tick(15)
        self.assertEqual(self.weapon_field(), 'Mod.Revolver')
        self.assertEqual(self.slot('Holster Right'), 'Mod.Revolver')
        self.assertEqual(self.eq('stats.adopted'), 0)


class SoloSwapTests(SwapBase):
    mode = 'solo'

    def armed_solo(self):
        self.npc()
        self.give_pistol_ammo()
        self.h.tick(6)                                    # passage d'affichage : pistolet accroché
        self.assertEqual(self.slot('Holster Right'), PISTOL)

    def test_solo_adopts_then_aims_with_the_replacement_in_both_hands(self):
        self.armed_solo()
        pistols = self.ev(f'CREATED_TYPES["{PISTOL}"]')
        self.swap('Mod.SMG')
        self.h.tick(3)
        self.assertEqual(self.weapon_field(), 'Mod.SMG')
        self.assertIs(self.ev(f'rawequal({self.body()}:getAttachedItem("Rifle On Back"), SWAPPED_OBJ)'), True)
        self.assertIsNone(self.slot('Holster Right'))
        self.run_lua('LivingKnox.Anim.setGesture("lk-1", "aim")')
        self.h.tick(6)
        self.assertIs(self.ev(f'rawequal({self.body()}:getPrimaryHandItem(), SWAPPED_OBJ)'), True)
        self.assertIs(self.ev(f'rawequal({self.body()}:getSecondaryHandItem(), SWAPPED_OBJ)'), True)
        self.assertIsNone(self.slot('Rifle On Back'))
        self.run_lua('LivingKnox.Anim.setGesture("lk-1", "idle")')
        self.h.tick(6)
        self.assertIs(self.ev(f'rawequal({self.body()}:getAttachedItem("Rifle On Back"), SWAPPED_OBJ)'), True)
        self.assertEqual(self.ev(f'CREATED_TYPES["{PISTOL}"]'), pistols)
        self.assertEqual(self.eq('stats.adopted'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_solo_death_keeps_the_replacing_weapon_and_its_ammo(self):
        self.armed_solo()
        self.swap('Mod.SMG')
        self.h.tick(3)
        self.kill()
        content = self.content()
        self.assertNotIn(PISTOL, content)
        self.assertNotIn('Base.9mmClip', content)
        self.assertIn('Mod.Mag30#15', content)                    # chargeur de réserve converti
        self.assertIn('Mod.Mag30#9', content)                     # chargeur engagé rendu en objet à la mort
        self.assertEqual(content.count('Mod.Round9'), 4)
        self.assertIn('@Rifle On Back=Mod.SMG', content)
        self.assertEqual(self.h.errors('solo'), [])

    def test_replaced_after_the_last_pass_adopted_at_death(self):
        self.armed_solo()
        # Remplacement et mort dans le même appel Lua : aucun passage d'affichage entre les deux.
        self.run_lua(f'{self.body()}:setAttachedItem("Holster Right", instanceItem("Mod.SMG")) '
                     'assert(LivingKnox.Health.kill("lk-1"))')
        self.h.tick(2)
        content = self.content()
        self.assertNotIn(PISTOL, content)
        self.assertIn('Mod.Mag30#9', content)
        self.assertIn('@Rifle On Back=Mod.SMG', content)
        self.assertEqual(self.ev('LivingKnox.Loot.stats.weaponsCreated'), 0)

    def test_suite_lk_weaponswap_passes_on_the_doubles(self):
        self.init()
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.weaponswap", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.weaponswap')
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.h.move_player('A', 100.5, 100.5)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.weaponswap", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(8000):
            self.h.tick()
            self.h.load('solo', 'for id in pairs(HARNESS.zombies) do STEP(id, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertTrue(report.ok, results)
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKW] measure')]
        self.assertTrue(any('adopted Base.Shotgun' in line for line in measures), measures)


class SourceTests(unittest.TestCase):
    def test_sources_are_kahlua_safe(self):
        for path in (LUA / EQUIPMENT, LUA / AMMO, LUA / COMBAT, DEV_LUA / SUITE):
            raw = path.read_bytes()
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), path)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.'):
                self.assertIsNone(re.search(pattern, code), (path, pattern))

    def test_suite_is_ascii(self):
        self.assertTrue(all(b < 128 for b in (DEV_LUA / SUITE).read_bytes()))


if __name__ == '__main__':
    unittest.main()
