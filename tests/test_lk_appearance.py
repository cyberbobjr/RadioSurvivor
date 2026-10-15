"""Tests hors jeu de l'apparence des PNJ Living Knox (LK02-T03, LK02-T12) : profils, tirage, application, registre
schéma 2, vêtements concrets rejoués quand la liste des tenues change.

    python RadioSurvivor/tests/test_lk_appearance.py

Banc tests/harness.py et doublures de tests/test_lk_bodies.py (création B), complétées ici. Les doublures reproduisent
le Java 42.21.0 relevé ; elles NE PROUVENT PAS l'API réelle, seulement la logique du mod :
- habillage : addZombiesInOutfit pose un identifiant de tenue persistante (bit 31 femme, tenue << 16, variante
  1..500, PersistentOutfits.java:142-189) et des visuels sales et troués (addRandomBloodDirtHolesEtc) ;
  dressInPersistentOutfitID rejoue la tenue (visuels effacés puis recréés, IsoZombie.java:3904-3915) ;
- HumanVisual : peau, coupe, barbe (nil pour une femme, HumanVisual.java:263-270), couleurs ImmutableColor
  (surcharge float, Math.min(x, 1), getRedInt = (int)(r x 255)) ;
- ItemVisual : removeHole / removePatch par index de partie (0..16, hors bornes = exception), removeBlood, removeDirt ;
- DoZombieInventory : objets portés créés depuis les visuels (WornItems.java:143-160) ; cadavre et réanimation
  copient visuel, objets portés et accrochés (IsoDeadBody.java:323-333, 1854-1856) ;
- LK02-T12 : l'habillage par identifiant dépend de l'index de la tenue ET de la variante (OUTFIT_SHIFT décale
  l'index comme une tenue ajoutée par un mod, PersistentOutfits.initOutfitList) ; ItemVisual.new et ses champs
  (ItemVisual.java:46-213), pickUninitializedValues qui tire une teinte flottante ; MISSING_ITEMS = objet retiré.
"""
from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import Base, lua_list, LUA, DEV_LUA  # noqa: E402

MOD_FILES = [LUA / 'shared' / 'LivingKnox' / 'LK_Appearance.lua']
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKAppearance.lua']
LOOKS = ['manFairBeard', 'manDarkGoatee', 'manBlondShaven', 'manOliveChops', 'manElderMoustache',
         'womanFairBun', 'womanTanBob', 'womanDarkPonytail', 'womanBlondLong', 'womanBrownKate']

# Lectures de la suite en jeu sur les doublures : parties, saleté par partie, objets portés et leur état.
EXTRA = r'''
local H = HARNESS
local C = H.classes
BloodBodyPartType.FromIndex = function(i) H.num(i, 'FromIndex'); return { index = i } end
function C.HumanVisual:getDirt(part) return (self.dirt and part.index == 0) and 0.5 or 0 end
function C.ItemVisual:getDirt(part) return (part.index == 0) and self.dirt or 0 end
function C.ItemVisual:getDenimPatch() return 0 end
function C.ItemVisual:getLeatherPatch() return 0 end
-- LK02-T12 bis : emplacements des vêtements (groupe BodyLocations "Human"). WornItems.setFromItemVisuals crée les
-- objets un par un ; setItem retire l'objet d'un emplacement exclusif du nouveau et insère le nouveau à l'index de son
-- emplacement dans le groupe (WornItems.java:57-80, 143-160) : les visuels du joueur réanimé suivent cet ordre.
-- BODY_RANK[<type sans @...>] = index de l'emplacement (nil = ordre des visuels gardé, comme avant) ; un mod qui
-- réordonne le groupe (BodyLocations.reset puis recréation) change ces index. EXCLUSIVE[a] = b : emplacements
-- exclusifs (setExclusive), le dernier posé gagne.
BODY_RANK, EXCLUSIVE = nil, { none = true }
local function baseType(iv) return string.match(iv.type, '^([^@]*)') end
local doZombieInventory = C.IsoZombie.DoZombieInventory
function C.IsoZombie:DoZombieInventory()
    doZombieInventory(self)
    if BODY_RANK == nil and EXCLUSIVE.none then return end
    local kept = {}
    for _, iv in ipairs(self.worn.items) do
        local t = baseType(iv)
        for i = #kept, 1, -1 do
            local o = baseType(kept[i])
            if EXCLUSIVE[t] == o or EXCLUSIVE[o] == t then table.remove(kept, i) end
        end
        local at = #kept + 1
        for i, o in ipairs(kept) do
            if BODY_RANK and (BODY_RANK[baseType(o)] or 0) > (BODY_RANK[t] or 0) then at = i; break end
        end
        table.insert(kept, at, iv)
    end
    self.worn = H.list(kept)
end
-- Mods actifs (getActivatedMods, liste Java) : MODS modifiable entre deux passes.
MODS = { 'batman_RadioSurvivor', 'batman_RadioSurvivorTests' }
getActivatedMods = function() return H.list(MODS) end
function C.IsoZombie:getWornItems()  -- WornItems.addItemsToItemContainer : état = max - 3 x trous
    local out = H.list()
    local src = (not rawget(self, 'reanimated') and rawget(self, 'worn')) or self:getItemVisuals()
    for _, iv in ipairs(src.items) do
        local holes = iv:getHolesNumber()
        out:add({ getItem = function() return { getCondition = function() return 10 - 3 * holes end,
            getConditionMax = function() return 10 end } end })
    end
    return out
end
'''


def float32(x: float) -> float:
    return struct.unpack('f', struct.pack('f', x))[0]


class AppearanceBase(Base):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, EXTRA)
        return h

    def body(self, i=0):
        return self.ev(f'getCell():getZombieList():get({i})')

    def profile(self, npc_id='lk-1'):
        return self.ev(f'LivingKnox.Store.data().npcs["{npc_id}"].profile')

    def write_slot(self, slot, seq, data_lua):
        self.run_lua(f'''
            local Codec = require "RadioSurvivor/RS_Codec"
            local body = Codec.encodeBytes({data_lua})
            local w = getFileWriter(LivingKnox.Store.state.path .. "-{slot}.txt", true, false)
            w:write("LKREG1={seq}\\n" .. Codec.hexBytes(body) .. "\\n" .. Codec.checksumBytes(body) .. "\\nend\\n")
            w:close()''')


class ApplyTests(AppearanceBase):
    def test_named_look_is_applied_before_the_inventory_and_the_corpse(self):
        self.init()
        npc_id, body = self.spawn(profile='{ look = "manFairBeard" }')
        self.assertEqual(npc_id, 'lk-1')
        calls = [c for c in self.calls() if not c.startswith('removeFrom')]
        self.assertEqual(calls[0], 'addZombiesInOutfit:Generic01:0')
        self.assertTrue(calls[1].startswith('dress:'))
        self.assertEqual(calls[2:], ['clearAttachedItems', 'DoZombieInventory:1000', 'createCorpse:zombie:1000',
                                     'reanimate'])
        hv = body.hv
        self.assertEqual((hv.skin, hv.hair, hv.beard), ('MaleBody01', 'Short', 'Full'))
        color = self.ev('{ getCell():getZombieList():get(0):getHumanVisual():getHairColor():getRedInt(), '
                        'getCell():getZombieList():get(0):getHumanVisual():getHairColor():getGreenInt(), '
                        'getCell():getZombieList():get(0):getHumanVisual():getHairColor():getBlueInt() }')
        self.assertEqual(lua_list(color), [111, 87, 60])  # brown, MainCreationMethods.lua:6344
        for f in ('BeardColor', 'NaturalHairColor', 'NaturalBeardColor'):
            self.assertIsNotNone(hv[f], f)
        self.assertEqual((hv.blood, hv.dirt, len(hv.body['items'])), (False, False, 0))
        items = lua_list(body.ivs['items'])
        self.assertEqual(len(items), 3)
        for iv in items:
            self.assertEqual((self.count(iv.holes), self.count(iv.patches), iv.blood, iv.dirt), (0, 0, 0, 0))
        self.assertEqual(body.attached, 0)
        p = self.profile()
        self.assertEqual((p.look, p.female, p.outfit, p.preset, p.skin, p.hair, p.beard),
                         ('manFairBeard', False, 'Generic01', 'clean', 'MaleBody01', 'Short', 'Full'))
        self.assertEqual(calls[1], 'dress:' + str(11 * 65536 + p.variant))

    @staticmethod
    def count(t):
        return sum(1 for _ in t.items()) if t is not None else 0

    def test_woman_has_her_skin_and_no_beard(self):
        self.init()
        _, body = self.spawn(profile='{ look = "womanDarkPonytail" }')
        self.assertIn('addZombiesInOutfit:Generic03:100', self.calls())
        self.assertEqual((body.hv.skin, body.hv.hair), ('FemaleBody05', 'PonyTail'))
        self.assertIsNone(self.ev('getCell():getZombieList():get(0):getHumanVisual():getBeardModel()'))
        self.assertEqual(self.profile().beard, '')
        dress = [c for c in self.calls() if c.startswith('dress:')]
        self.assertEqual(len(dress), 1)
        self.assertLess(int(dress[0][6:]), 0)  # bit 31 : tenue de femme

    def test_every_profile_is_valid_and_applies(self):
        self.init()
        for i, look in enumerate(LOOKS):
            npc_id, body = self.spawn(102 + i, 102, 0, f'{{ look = "{look}" }}')
            self.assertIsNotNone(npc_id, f'{look}: {body}')
            p = self.profile(npc_id)
            self.assertEqual(body.hv.skin, p.skin, look)
            self.assertTrue(body.hv.skin.startswith('FemaleBody' if p.female else 'MaleBody'), look)
        self.assertEqual(sorted(lua_list(self.ev('LivingKnox.Appearance.lookNames()'))), sorted(LOOKS))

    def test_reincarnation_redresses_with_the_same_variant_and_profile(self):
        self.init()
        _, first = self.spawn(profile='{ look = "manOliveChops" }')
        before = [iv.type for iv in lua_list(first.ivs['items'])]
        profile = dict(self.profile().items())
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 1))
        second = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        after = [iv.type for iv in lua_list(second.ivs['items'])]
        self.assertEqual(before, after)
        self.assertTrue(all(t.endswith('#' + str(profile['variant'])) for t in after), after)
        dress = [c for c in self.calls() if c.startswith('dress:')]
        self.assertEqual(len(set(dress)), 1)  # même identifiant de tenue rejoué
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].generation'), 2)
        self.assertTrue(self.ev('LivingKnox.Appearance.same(LivingKnox.Store.data().npcs["lk-1"].profile, '
                                'LivingKnox.Appearance.normalize({ look = "manOliveChops" }, 1))'))
        self.assertEqual((second.hv.skin, second.hv.hair, second.hv.beard), (profile['skin'], 'Messy', 'Chops'))

    def test_bad_inputs_are_refused_before_anything_is_created(self):
        self.init()
        cases = {
            '{ look = "zombie" }': 'unknown look zombie',
            '{ look = "womanTanBob", female = false }': 'does not match profile.female',
            '{ female = true, beard = "Full" }': 'a woman has no beard',
            '{ hair = "Bob", female = false }': 'unknown hair Bob for this sex',
            '{ skin = "M_ZedBody01_level1", female = false }': 'is not a human skin',
            '{ skin = "FemaleBody01", female = false }': 'is not a human skin',
            '{ hairColor = { r = 300, g = 0, b = 0 } }': 'hairColor must be',
            '{ hairColor = { r = 1, g = 2, b = 3, a = 4 } }': 'hairColor must be',
            '{ variant = 0 }': 'variant must be',
            '{ variant = 1.5 }': 'variant must be',
            '{ outfit = "Police" }': 'unknown outfit Police',
            '{ hat = 1 }': 'unknown profile field hat',
            '{ look = 3 }': 'profile.look must be a string',
        }
        for bad, why in cases.items():
            npc_id, msg = self.spawn(profile=bad)
            self.assertIsNone(npc_id, bad)
            self.assertIn(why, msg, bad)
        self.assertEqual([c for c in self.calls() if c.startswith('addZombies')], [])
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 1)


class DrawTests(AppearanceBase):
    def test_draw_is_deterministic_spread_and_respects_the_sex(self):
        names, women = set(), set()
        for seed in range(1, 301):
            a = self.ev(f'LivingKnox.Appearance.normalize({{}}, {seed})')
            b = self.ev(f'LivingKnox.Appearance.normalize({{}}, {seed})')
            self.assertTrue(self.ev(f'LivingKnox.Appearance.same(LivingKnox.Appearance.normalize({{}}, {seed}), '
                                    f'LivingKnox.Appearance.normalize({{}}, {seed}))'))
            self.assertEqual((a.look, a.variant), (b.look, b.variant))
            self.assertTrue(1 <= a.variant <= 500)
            names.add(a.look)
            w = self.ev(f'LivingKnox.Appearance.normalize({{ female = true }}, {seed})')
            self.assertTrue(w.female)
            women.add(w.look)
        self.assertEqual(names, set(LOOKS))
        self.assertEqual(women, {n for n in LOOKS if n.startswith('woman')})

    def test_spawn_draws_with_the_npc_number(self):
        self.init()
        for n in range(1, 6):
            npc_id, _ = self.spawn(100 + n, 102)
            self.assertEqual(npc_id, f'lk-{n}')
            self.assertTrue(self.ev(f'LivingKnox.Appearance.same(LivingKnox.Store.data().npcs["lk-{n}"].profile, '
                                    f'LivingKnox.Appearance.normalize({{}}, {n}))'), n)

    def test_outfit_id_with_variant_without_bit_operators(self):
        f = 'LivingKnox.Appearance.outfitIdWithVariant'
        self.assertEqual(self.ev(f'{f}({11 * 65536 + 7}, 42)'), 11 * 65536 + 42)
        female = -2 ** 31 + 12 * 65536 + 500
        self.assertEqual(self.ev(f'{f}({female}, 3)'), -2 ** 31 + 12 * 65536 + 3)
        hat = 11 * 65536 + 32768 + 7
        self.assertEqual(self.ev(f'{f}({hat}, 9)'), 11 * 65536 + 32768 + 9)
        for bad in ('0, 5', f'{11 * 65536}, 5', f'{11 * 65536 + 7}, 0', f'{11 * 65536 + 7}, 501', '"x", 5'):
            self.assertIsNone(self.ev(f'{f}({bad})'), bad)

    def test_hair_colour_bytes_round_trip_in_float32(self):
        # ImmutableColor(float x4) garde (float)(c / 255) ; getRedInt / l'octet sauvegardé = (int)(r * 255f), produit
        # float arrondi (exact en double puis arrondi en float32, comme Java).
        for c in range(256):
            r = min(float32(c / 255), 1.0)
            self.assertEqual(int(float32(r * float32(255.0))), c, c)


class RegistryTests(AppearanceBase):
    SCHEMA1 = ('{ schema = 1, nextId = 4, npcs = { '
               '["lk-1"] = { id = "lk-1", generation = 1, state = "embodied", '
               'profile = { female = true, outfit = "Generic03", preset = "clean" }, want = { x = 1, y = 2, z = 0 } }, '
               '["lk-3"] = { id = "lk-3", generation = 0, state = "virtual", '
               'profile = { female = false, outfit = "Generic05", preset = "clean" }, want = { x = 4, y = 5, z = 0 } } } }')

    def test_schema_1_registry_is_migrated_and_rewritten(self):
        self.init()
        self.write_slot(0, 7, self.SCHEMA1)
        self.init()
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)
        self.assertEqual(self.ev('LivingKnox.Store.data().schema'), 2)
        self.assertEqual(self.ev('LivingKnox.Store.state.seq'), 8)  # réécrit au schéma 2
        p1, p3 = self.profile('lk-1'), self.profile('lk-3')
        self.assertEqual((p1.female, p1.outfit), (True, 'Generic03'))
        self.assertTrue(p1.look.startswith('woman'))
        self.assertEqual((p3.female, p3.outfit), (False, 'Generic05'))
        self.assertTrue(p3.look.startswith('man'))
        self.assertTrue(self.ev('LivingKnox.Appearance.same(LivingKnox.Store.data().npcs["lk-3"].profile, '
                                'LivingKnox.Appearance.normalize({ female = false, outfit = "Generic05" }, 3))'))
        self.assertTrue(any('registry migrated from schema 1 to 2' in line for line in self.lk()))
        before = len([line for line in self.lk() if 'migrated' in line])
        self.init()
        self.assertEqual(len([line for line in self.lk() if 'migrated' in line]), before)  # déjà au schéma 2
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 4)

    def test_bad_schema_1_profile_blocks_the_registry(self):
        self.init()
        self.write_slot(0, 7, self.SCHEMA1.replace('female = true', 'female = "yes"'))
        self.init()
        blocked, why = self.run_lua('return LivingKnox.Store.isBlocked()')
        self.assertTrue(blocked)
        self.assertIn('npc lk-1: bad profile', why)

    def test_stored_values_survive_a_change_of_the_profile_table(self):
        self.init()
        self.spawn(profile='{ look = "manFairBeard" }')
        stored = dict(self.profile().items())
        # Version ultérieure : profil modifié, puis renommé ; le registre garde ses valeurs résolues.
        self.run_lua('LivingKnox.Appearance.look("manFairBeard").hair = "Bald"')
        self.init()
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)
        self.assertEqual(self.profile().hair, stored['hair'])
        self.run_lua('LivingKnox.Store.data().npcs["lk-1"].profile.look = "renamedLook"; LivingKnox.Store.save()')
        self.init()
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)  # profil complet : nom inconnu admis
        self.run_lua('LivingKnox.Store.data().npcs["lk-1"].profile.skin = nil; LivingKnox.Store.save()')
        self.init()
        blocked, why = self.run_lua('return LivingKnox.Store.isBlocked()')
        self.assertTrue(blocked)
        self.assertIn('unknown look renamedLook', why)


def clothes_of(body):
    """Ce que le client dessine pour chaque visuel : type, ClothingItem, teinte en octets, décalage, textures, décal."""
    out = []
    for iv in lua_list(body.ivs['items']):
        tint = iv.tint
        out.append((iv.type, iv.item, tint and tuple(int(tint[k] * 255) for k in ('r', 'g', 'b')), iv.hue, iv.base,
                    iv.choice, iv.decal))
    return out


class ClothesTests(AppearanceBase):
    """LK02-T12 : vêtements concrets relevés au premier corps et rejoués, indépendants de l'index des tenues."""

    def embody_again(self, npc_id='lk-1'):
        self.assertEqual(self.run_lua(f'return LivingKnox.Bodies.despawn("{npc_id}")'), (True, 1))
        body = self.run_lua(f'return LivingKnox.Bodies.embody("{npc_id}", 102, 102, 0)')
        self.assertNotIsInstance(body, str)
        return body

    @staticmethod
    def count(t):
        return sum(1 for _ in t.items()) if t is not None else 0

    def test_first_body_records_its_clothes_with_fixed_values(self):
        self.init()
        _, body = self.spawn(profile='{ look = "manOliveChops" }')
        self.assertGreater(self.ev('PICKED'), 0)  # teinte du t-shirt tirée avant DoZombieInventory
        clothes = lua_list(self.ev('LivingKnox.Store.data().npcs["lk-1"].clothes'))
        self.assertEqual(len(clothes), 3)
        self.assertEqual(self.ev('LivingKnox.Appearance.clothesKey(LivingKnox.Store.data().npcs["lk-1"].clothes)'),
                         self.ev('LivingKnox.Appearance.clothesKey(LivingKnox.Appearance.describe('
                                 'getCell():getZombieList():get(0)))'))
        shirt = clothes[0]
        self.assertEqual((shirt.tint.r, shirt.tint.g, shirt.tint.b), (31, 166, 127))  # (int)(x * 255) de 0.123456...
        # Teinte du corps ramenée aux octets : ImmutableColor(c / 255), comme le descripteur reçu par les clients.
        self.assertEqual(clothes_of(body)[0][2], (31, 166, 127))
        self.assertEqual(lua_list(body.ivs['items'])[0].tint.r, 31 / 255)
        self.assertEqual(shirt.item, 'Base.TshirtItem')
        self.assertTrue(any('npc lk-1 clothes recorded (3 item(s))' in line for line in self.lk()))
        self.init()  # relu et validé
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)
        self.assertEqual(len(lua_list(self.ev('LivingKnox.Store.data().npcs["lk-1"].clothes'))), 3)

    def test_shifted_outfit_index_changes_nothing_for_a_recorded_npc(self):
        self.init()
        _, first = self.spawn(profile='{ look = "manOliveChops" }')
        before = clothes_of(first)
        key = self.ev('LivingKnox.Appearance.clothesKey(LivingKnox.Store.data().npcs["lk-1"].clothes)')
        self.run_lua('OUTFIT_SHIFT = 3')  # un mod ajoute trois tenues avant Generic04
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 1))
        self.run_lua('CALLS = {}')
        second = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        self.assertEqual(clothes_of(second), before)
        self.assertEqual([c for c in self.calls() if c.startswith('dress:')], [])  # variante non rejouée
        self.assertEqual(self.calls()[:2], ['addZombiesInOutfit:Generic04:0', 'clearAttachedItems'])
        for iv in lua_list(second.ivs['items']):
            self.assertEqual((self.count(iv.holes), self.count(iv.patches), iv.blood, iv.dirt), (0, 0, 0, 0))
        self.assertEqual(second.attached, 0)
        self.assertEqual(self.ev('LivingKnox.Appearance.clothesKey(LivingKnox.Store.data().npcs["lk-1"].clothes)'),
                         key)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].generation'), 2)

    def test_without_recorded_clothes_the_shift_would_dress_otherwise(self):
        # Témoin : le banc détecte bien le problème de LK02-T12 (rejouer la variante après un décalage d'index).
        self.init()
        _, first = self.spawn(profile='{ look = "manOliveChops" }')
        before = clothes_of(first)
        self.run_lua('OUTFIT_SHIFT = 3')
        self.run_lua('LivingKnox.Bodies.despawn("lk-1"); LivingKnox.Store.data().npcs["lk-1"].clothes = nil')
        second = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        self.assertNotEqual([c[0] for c in clothes_of(second)], [c[0] for c in before])
        self.assertNotEqual(clothes_of(second), before)

    def test_npc_created_before_t12_keeps_its_current_clothes(self):
        # Registre et corps d'avant LK02-T12 : aucun champ clothes. Le corps présent est relevé à sa liaison.
        self.init()
        _, old = self.spawn(profile='{ look = "womanTanBob" }')
        before = clothes_of(old)
        self.run_lua('LivingKnox.Store.data().npcs["lk-1"].clothes = nil; LivingKnox.Store.save()')
        self.init()  # relu sans clothes : valide, aucune migration de schéma
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)
        self.assertEqual(self.ev('LivingKnox.Store.data().schema'), 2)
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"].clothes'))
        self.run_lua('LivingKnox.Bodies.bound = {}; OUTFIT_SHIFT = 2')  # redémarrage : corps à relier ; mod ajouté
        self.run_lua('LivingKnox.Bodies.scanAll()')
        self.assertEqual(len(lua_list(self.ev('LivingKnox.Store.data().npcs["lk-1"].clothes'))), 3)
        self.assertTrue(self.ev('LivingKnox.Store.state.dirty'))
        second = self.embody_again()
        self.assertEqual(clothes_of(second), before)

    def test_removed_clothing_item_is_left_out_and_logged(self):
        self.init()
        _, first = self.spawn(profile='{ look = "manOliveChops" }')
        before = clothes_of(first)
        self.run_lua('MISSING_ITEMS["' + before[1][0] + '"] = true')  # mod du pantalon retiré
        second = self.embody_again()
        self.assertEqual(clothes_of(second), [before[0], before[2]])
        self.assertTrue(any('WARN npc lk-1: 1 recorded clothing item(s) no longer exist' in line for line in self.lk()),
                        self.lk())
        self.assertEqual(len(lua_list(self.ev('LivingKnox.Store.data().npcs["lk-1"].clothes'))), 3)  # gardé

    def test_all_clothing_items_removed_falls_back_to_the_variant(self):
        self.init()
        _, first = self.spawn(profile='{ look = "manOliveChops" }')
        code = ''.join('MISSING_ITEMS["' + c[0] + '"] = true; ' for c in clothes_of(first))
        self.run_lua(code)
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 1))
        self.run_lua('CALLS = {}')
        second = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        self.assertEqual(len([c for c in self.calls() if c.startswith('dress:')]), 1)
        self.assertEqual(len(clothes_of(second)), 3)

    def test_reordered_body_locations_keep_the_same_clothes(self):
        # Essai en jeu du 2026-10-13 : un mod de vêtements recrée le groupe BodyLocations et place les chaussures
        # après le pantalon. Les visuels du corps suivent l'ordre des emplacements : mêmes vêtements, autre ordre.
        self.init()
        _, first = self.spawn(profile='{ look = "womanTanBob" }')
        before = clothes_of(first)
        key = self.ev('LivingKnox.Appearance.clothesKey(LivingKnox.Store.data().npcs["lk-1"].clothes)')
        self.run_lua('BODY_RANK = { ["Base.Tshirt"] = 1, ["Base.Shoes"] = 2, ["Base.Trousers"] = 3 }')
        second = self.embody_again()
        after = clothes_of(second)
        self.assertEqual(sorted(after, key=repr), sorted(before, key=repr))
        self.assertNotEqual(after, before)  # ordre changé : une comparaison ordonnée échouerait
        now = 'LivingKnox.Appearance.describe(getCell():getZombieList():get(0))'
        self.assertNotEqual(self.ev(f'LivingKnox.Appearance.clothesKey({now})'), key)
        self.assertIs(self.ev('LivingKnox.Appearance.sameClothes(LivingKnox.Store.data().npcs["lk-1"].clothes, '
                              f'{now})'), True)
        self.assertFalse(any('WARN' in line for line in self.lk()), self.lk())

    def test_exclusive_body_locations_leave_out_a_garment_with_a_warning(self):
        self.init()
        _, first = self.spawn(profile='{ look = "womanTanBob" }')
        before = clothes_of(first)
        self.run_lua('EXCLUSIVE = { ["Base.Shoes"] = "Base.Trousers" }')  # emplacements devenus exclusifs
        second = self.embody_again()
        self.assertEqual(clothes_of(second), [before[0], before[2]])  # le dernier posé (chaussures) gagne
        self.assertTrue(any('WARN npc lk-1: 1 recorded clothing item(s) could not be worn with the others' in line
                            for line in self.lk()), self.lk())
        self.assertEqual(len(lua_list(self.ev('LivingKnox.Store.data().npcs["lk-1"].clothes'))), 3)  # gardé

    def test_clothes_diff_ignores_the_order_and_pairs_by_type(self):
        d = self.run_lua('''
            local A = LivingKnox.Appearance
            local d = A.diffKeys({ "Base.A|a|-|1,2,3|-|0|-|-", "Base.B|b|-|-|-|-|-|-", "Base.C|c|-|-|-|-|-|-",
                "Base.C|c|-|-|-|-|-|-" }, { "Base.C|c|-|-|-|-|-|-", "Base.B|b|-|-|-|-|-|-", "Base.A|a|-|9,2,3|-|0|-|-",
                "Base.D|d|-|-|-|-|-|-" })
            local same = A.diffKeys({ "x|1", "y|2" }, { "y|2", "x|1" })
            return { removed = table.concat(d.removed, ","), added = table.concat(d.added, ","),
                changed = #d.changed == 1 and (d.changed[1].from .. ">" .. d.changed[1].to) or #d.changed,
                same = #same.removed + #same.added + #same.changed }''')
        self.assertEqual(d.removed, 'Base.C|c|-|-|-|-|-|-')
        self.assertEqual(d.added, 'Base.D|d|-|-|-|-|-|-')
        self.assertEqual(d.changed, 'Base.A|a|-|1,2,3|-|0|-|->Base.A|a|-|9,2,3|-|0|-|-')
        self.assertEqual(d.same, 0)
        self.assertIs(self.ev('LivingKnox.Appearance.itemExists("Base.Tshirt")'), True)
        self.run_lua('MISSING_ITEMS["Base.Tshirt"] = true')
        self.assertIs(self.ev('LivingKnox.Appearance.itemExists("Base.Tshirt")'), False)
        self.assertIs(self.ev('LivingKnox.Appearance.itemExists("Tshirt")'), False)

    def test_bad_clothes_block_the_registry(self):
        self.init()
        self.spawn(profile='{ look = "manOliveChops" }')
        cases = {
            '{}': 'clothes must list 1 to 64 entries',
            '{ { type = "Base.Tshirt" }, nil, { type = "Base.Shoes" } }': 'clothes is not a list (gap)',
            '{ [2] = { type = "Base.Tshirt" }, [3] = { type = "Base.Shoes" } }': 'clothes entry 1: entry is not a table',
            '{ x = { type = "Base.Tshirt" } }': 'clothes is not a list',
            '{ { type = "Tshirt" } }': 'bad item type',
            '{ { type = "Base.Tshirt", tint = { r = 256, g = 0, b = 0 } } }': 'bad tint',
            '{ { type = "Base.Tshirt", hue = 2 } }': 'bad hue',
            '{ { type = "Base.Tshirt", base = 1.5 } }': 'bad base texture',
            '{ { type = "Base.Tshirt", choice = -1 } }': 'bad texture choice',
            '{ { type = "Base.Tshirt", decal = "" } }': 'bad decal',
            '{ { type = "Base.Tshirt", colour = 1 } }': 'unknown field colour',
            '"Base.Tshirt"': 'clothes is not a list',
        }
        for bad, why in cases.items():
            ok, msg = self.run_lua(f'return LivingKnox.Appearance.validClothes({bad})')
            self.assertFalse(ok, bad)
            self.assertIn(why, msg, bad)
        self.assertIs(self.ev('LivingKnox.Appearance.validClothes({ { type = "Mod-X.Shirt_01+b", hue = -1, base = 0, '
                              'choice = 127, tint = { r = 0, g = 255, b = 9 }, item = "a", alt = "b", '
                              'decal = "c" } })'), True)
        self.run_lua('LivingKnox.Store.data().npcs["lk-1"].clothes[1].hue = 5; LivingKnox.Store.save()')
        self.init()
        blocked, why = self.run_lua('return LivingKnox.Store.isBlocked()')
        self.assertTrue(blocked)
        self.assertIn('npc lk-1: clothes entry 1: bad hue', why)


class SoloSuiteTests(AppearanceBase):
    mode = 'solo'

    def test_suite_passes_on_the_doubles(self):
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.h.load('solo', 'shared/RST/suites/RST_LKAppearance.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.appearance", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.appearance')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertEqual(listed.count, 6)
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.appearance", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(200):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 6, results)
        self.assertTrue(report.ok, results)
        # LK02-T12 across a restart: run 1 keeps a virtual npc and SKIPs with the instruction; run 2 (same mods here)
        # embodies it, compares, forgets it and SKIPs because the mod list did not change.
        restart = [r for r in results if 'restart' in r[0]]
        self.assertEqual([r[1] for r in restart], ['SKIP'], restart)
        self.assertIn('phase 1 done', restart[0][2])
        self.assertEqual(self.h.eval('solo', '#LivingKnox.Bodies.list()'), 1)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.appearance", tags = "world", '
                                          'test = "restart" }, { ctx = { player = getPlayer() } }))'), True)
        for _ in range(200):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report2 = self.h.eval('solo', 'RST.last()')
        results2 = [(r.test, r.status, r.message) for r in lua_list(report2.results)]
        self.assertEqual([r[1] for r in results2], ['SKIP'], results2)
        self.assertIn('mod list did not change', results2[0][2])
        self.assertEqual(self.h.eval('solo', 'getCell():getZombieList():size()'), 0)
        self.assertEqual(self.h.eval('solo', '#LivingKnox.Bodies.list()'), 0)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKA] measure')]
        self.assertTrue(any('reincarnation same=true' in line for line in measures), measures)
        self.assertTrue(any('replay same=true clothes=3' in line for line in measures), measures)

    def run_restart(self):
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.appearance", tags = "world", '
                                          'test = "restart" }, { ctx = { player = getPlayer() } }))'), True)
        for _ in range(200):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.status, r.message, lua_list(r.notes) if r.notes else []) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        return results[0]

    def record(self):
        path = self.h.file_root('solo') / 'batman_RadioSurvivor' / 'tests' / 'lk-appearance-restart.txt'
        return path.read_text(encoding='utf-8') if path.exists() else None

    def test_restart_with_reordered_body_locations_passes_and_reports_garment_by_garment(self):
        # Défaut de l'essai du 2026-10-13 : même vêtements, ordre des emplacements changé par un mod de vêtements.
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.h.load('solo', 'shared/RST/suites/RST_LKAppearance.lua')
        status, message, notes = self.run_restart()
        self.assertEqual(status, 'SKIP')
        self.assertIn('phase 1 done', message)
        self.assertIn('no record file', message)
        record = self.record()
        self.assertEqual(record.count('item='), 3, record)
        self.assertIn('body=FemaleBody03 Bob', record)
        self.assertTrue(any(n.startswith('restart phase 1 item 3: ') for n in notes), notes)
        # Redémarrage avec un mod de vêtements : chaussures après le pantalon, liste de mods changée.
        self.h.load('solo', 'BODY_RANK = { ["Base.Tshirt"] = 1, ["Base.Shoes"] = 2, ["Base.Trousers"] = 3 }; '
                            'MODS[#MODS + 1] = "SomeClothesMod"; return true')
        status, message, notes = self.run_restart()
        self.assertEqual(status, 'PASS', (message, notes))
        self.assertTrue(any('body same, clothes 3 recorded, 0 difference(s), 0 left out, mods added {SomeClothesMod}'
                            in n for n in notes), notes)
        self.assertEqual(self.record(), '')  # passe 2 réussie : fiche vidée, PNJ oublié
        self.assertEqual(self.h.eval('solo', '#LivingKnox.Bodies.list()'), 0)

    def test_failed_restart_keeps_the_record_and_lists_every_difference(self):
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.h.load('solo', 'shared/RST/suites/RST_LKAppearance.lua')
        self.assertEqual(self.run_restart()[0], 'SKIP')
        record = self.record()
        npc_id = self.h.eval('solo', 'LivingKnox.Bodies.list()[1].id')
        # Défaut simulé : un vêtement rejoué autrement (teinte), un autre retiré avec son mod.
        self.h.load('solo', f'local c = LivingKnox.Store.data().npcs["{npc_id}"].clothes; ORIG_TINT = c[1].tint; '
                            'c[1].tint = { r = 1, g = 2, b = 3 }; MISSING_ITEMS[c[3].type] = true; return true')
        self.h.load('solo', 'MODS[#MODS + 1] = "SomeClothesMod"; return true')
        status, message, notes = self.run_restart()
        self.assertEqual(status, 'FAIL', (message, notes))
        self.assertIn('clothes differences after the restart', message)
        self.assertTrue(any(n.startswith('restart phase 2 changed: Base.Tshirt') and '|1,2,3|' in n for n in notes),
                        notes)
        self.assertTrue(any(n.startswith('restart phase 2 left out (item type no longer exists): Base.Shoes')
                            for n in notes), notes)
        self.assertTrue(any('1 difference(s), 1 left out' in n for n in notes), notes)
        self.assertEqual(self.record(), record)  # fiche gardée
        self.assertEqual(self.h.eval('solo', f'LivingKnox.Store.data().npcs["{npc_id}"].state'), 'virtual')
        # Passe 2 relancée après correction : réussit sur la même fiche.
        self.h.load('solo', f'LivingKnox.Store.data().npcs["{npc_id}"].clothes[1].tint = ORIG_TINT; '
                            'MISSING_ITEMS = {}; return true')
        status, message, notes = self.run_restart()
        self.assertEqual(status, 'PASS', (message, notes))
        self.assertEqual(self.record(), '')

    def test_empty_record_makes_run_2_a_new_run_1(self):
        # Essai du 2026-10-13 : la fiche de la passe 1 a été vidée par l'échec de la passe 2.
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.h.load('solo', 'shared/RST/suites/RST_LKAppearance.lua')
        self.h.load('solo', 'local w = getFileWriter("batman_RadioSurvivor/tests/lk-appearance-restart.txt", true, '
                            'false); w:close(); return true')
        status, message, _ = self.run_restart()
        self.assertEqual(status, 'SKIP')
        self.assertIn('is empty', message)
        self.assertIn('phase 1 done', message)
        self.assertEqual(self.record().count('item='), 3)

    def test_dev_console_spawns_a_named_profile(self):
        self.h.load('solo', 'server/RST/RST_Server.lua')
        self.h.load('solo', 'server/RST/RST_LKBodiesServer.lua')
        self.h.load('solo', 'client/RST/RST_LKBodiesClient.lua')
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.assertIs(self.ev('LKB.spawn("womanTanBob")'), True)
        self.assertIs(self.ev('LKB.spawn("manElderMoustache", 3, 0)'), True)
        self.assertIs(self.ev('LKB.spawn("nobody")'), False)
        self.assertIs(self.ev('LKB.list()'), True)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKB]')]
        self.assertTrue(any('look=womanTanBob skin=FemaleBody03 hair=Bob beard=' in line for line in lines), lines)
        self.assertIn('[LKB] spawned lk-2 at 103,100,0', lines)
        self.assertTrue(any('spawn refused: unknown look nobody' in line for line in lines), lines)
        self.assertTrue(any('look=womanTanBob' in line and 'clothes=3' in line for line in lines), lines)
        # LK02-T12 : nouvelle incarnation depuis la console, vêtements relevés rejoués.
        self.assertIs(self.ev('LKB.despawn(2)'), True)
        self.assertIs(self.ev('LKB.embody(2, 3, 0)'), True)
        self.assertIs(self.ev('LKB.embody(2, 3, 0)'), False)  # déjà incarné
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKB]')]
        self.assertIn('[LKB] embodied lk-2 at 103,100,0', lines)
        self.assertTrue(any('embody refused: npc lk-2 is embodied' in line for line in lines), lines)
        self.assertIs(self.ev('LKB.clear()'), True)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_ascii_sources(self):
        import re
        for path in MOD_FILES + DEV_FILES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b', r'getPlayer\(\)'):
                self.assertIsNone(re.search(pattern, code), f'{path.name}: {pattern}')
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')


if __name__ == '__main__':
    unittest.main()
