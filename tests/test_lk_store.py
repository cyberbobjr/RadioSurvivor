"""Tests hors jeu de l'écriture regroupée du registre des PNJ (LK13-T10, LK_Store) et du tri des clés de RS_Codec.

    python RadioSurvivor/tests/test_lk_store.py

Banc tests/harness.py (serveur dédié + deux clients), doublures du banc des corps (tests/test_lk_bodies.py). Une
image du banc = OnTickEvenPaused puis OnTick (IngameState.java:1380, 1681). Règles vérifiées (fiche
docs/annexes/conception/corps-registre.md, « Persistance ») :
- les créations et retraits d'une même image sont écrits une fois, à la fin de l'image ; rien avant ;
- serveur en pause (OnTick absent) : écrit au début de l'image suivante ; OnSave et relecture (init) écrivent ce qui
  attend ;
- la mort d'un corps est écrite tout de suite (mort unique LK07-T04) ;
- relecture de contrôle à la première écriture de la session et sur demande seulement ;
- tri des clés de RS_Codec : mêmes octets que le comparateur historique (tables aléatoires, clés mêlées).
"""
from __future__ import annotations

import random
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import Base  # noqa: E402

READS = ('READS = 0 local orig = LivingKnox.Store.readSlotFile '
         'LivingKnox.Store.readSlotFile = function(...) READS = READS + 1 return orig(...) end')


class Bench(Base):
    def seq(self):
        return self.ev('LivingKnox.Store.state.seq')

    def raw_spawn(self, x=102, y=102):
        """Création sans fin d'image (plusieurs dans la même image)."""
        return self.run_lua(f'return LivingKnox.Bodies.spawn({{}}, {x}, {y}, 0)')

    def file_data(self):
        """Registre relu du fichier de la dernière écriture (nil si aucun)."""
        return self.ev('(function() local St = LivingKnox.Store if St.state.seq == 0 then return nil end '
                       'local r = St.readSlotFile(St.slotPath(St.state.seq % 2), St.HEADER) return r and r.data end)()')

    def restart(self):
        root = self.h.root
        self.h._tmp = None  # le dossier de fichiers survit au « redémarrage »
        self.h.close()
        self.h = self.make(root=root)
        self.addCleanup(shutil.rmtree, root, True)


class DeferredWriteTests(Bench):
    def test_creations_of_a_frame_written_once_at_its_end(self):
        self.init()
        self.assertEqual(self.seq(), 0)
        for i in range(3):
            self.assertEqual(self.raw_spawn(102 + 2 * i, 102)[0], f'lk-{i + 1}')
        self.assertEqual(self.seq(), 0)                       # rien écrit avant la fin de l'image
        self.assertTrue(self.ev('LivingKnox.Store.isQueued()'))
        self.assertEqual(self.registry_files(), [])
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)                       # trois créations, une écriture
        self.assertFalse(self.ev('LivingKnox.Store.isQueued()'))
        self.assertEqual(self.file_data().nextId, 4)
        self.h.tick(3)
        self.assertEqual(self.seq(), 1)                       # rien de changé : rien écrit
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 1))
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-2", true)'), (True, 1))
        self.assertEqual(self.seq(), 1)
        self.h.tick(1)
        self.assertEqual(self.seq(), 2)                       # deux retraits, une écriture
        self.restart()
        self.init()
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 4)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'virtual')
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-2"]'))
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-3"].state'), 'embodied')
        self.assertEqual(self.h.errors(self.srv), [])

    def test_weapon_set_at_creation_written_with_it(self):
        self.h.load(self.srv, 'shared/LivingKnox/LK_Equipment.lua')
        # Arme décrite et publication aux clients hors sujet ici (bancs tests/test_lk_equipment.py) : neutralisées.
        self.run_lua('local E = LivingKnox.Equipment E.spec = function(t) return { t = t, l = "Shovel Back" } end '
                     'E.serverPass = function() end E.publish = function() end')
        self.init()
        self.raw_spawn()
        self.assertEqual(self.run_lua('return LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")'), True)
        self.assertEqual(self.seq(), 0)
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)
        self.assertEqual(self.file_data().npcs['lk-1'].weapon, 'Base.BaseballBat')

    def test_end_of_frame_write_follows_later_subscribers(self):
        self.init()
        # Abonné inscrit après LK_Store, au chargement (comme LK_Bodies, LK_Decisions) : au premier OnTickEvenPaused,
        # l'écriture de fin d'image passe derrière lui.
        self.run_lua('N = 0 Events.OnTick.Add(function() N = N + 1 assert(LivingKnox.Store.markChanged()) end)')
        fn = self.ev('LivingKnox.handlers["OnTick/Store.flush"]')
        self.h.tick(1)
        self.assertEqual((self.seq(), self.ev('LivingKnox.Store.isQueued()')), (1, False))
        self.h.tick(2)
        self.assertEqual(self.seq(), 3)                       # une écriture par image, jamais deux
        self.h.server.g.SAME_A = fn
        self.assertTrue(self.ev('rawequal(SAME_A, LivingKnox.handlers["OnTick/Store.flush"])'))

    def test_paused_server_writes_at_the_next_frame_start(self):
        self.init()
        self.h.set_paused(self.srv, True)                     # serveur vide en pause : OnTickEvenPaused seul
        self.raw_spawn()
        self.h.tick(1)
        self.assertEqual(self.seq(), 0)                       # une image entière passe d'abord
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)
        self.assertFalse(self.ev('LivingKnox.Store.isQueued()'))

    def test_onsave_and_reload_write_what_is_queued(self):
        self.init()
        self.raw_spawn()
        self.h.fire(self.srv, 'OnSave')
        self.assertEqual((self.seq(), self.ev('LivingKnox.Store.isQueued()')), (1, False))
        self.raw_spawn(104, 102)
        self.init()                                           # relecture : l'écriture différée est faite d'abord
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 3)
        self.assertEqual(self.seq(), 2)

    def test_flush_writes_now_and_is_idempotent(self):
        self.init()
        self.assertTrue(self.ev('LivingKnox.Store.flush()'))          # rien en attente : à jour
        self.assertEqual(self.seq(), 0)
        self.raw_spawn()
        self.assertTrue(self.ev('LivingKnox.Store.flush()'))
        self.assertEqual(self.seq(), 1)
        self.assertTrue(self.ev('LivingKnox.Store.flush()'))
        self.h.tick(1)
        self.assertEqual(self.seq(), 1)
        self.run_lua('LivingKnox.Store.state.blocked = true')
        self.assertFalse(self.ev('LivingKnox.Store.markChanged()'))
        self.assertFalse(self.ev('LivingKnox.Store.flush()'))

    def test_death_is_written_at_once(self):
        self.init()
        self.raw_spawn()
        self.h.tick(1)
        self.raw_spawn(104, 102)                              # changement en attente dans la même image
        self.run_lua('local z = (LivingKnox.Bodies.find("lk-1")); '
                     'z:Hit(instanceItem("Base.BaseballBat"), HARNESS.players["A"], 2, false, 1.0)')
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'dead')
        self.assertEqual((self.seq(), self.ev('LivingKnox.Store.isQueued()')), (2, False))
        data = self.file_data()
        self.assertEqual((data.npcs['lk-1'].state, data.nextId), ('dead', 3))

    def test_readback_only_at_the_first_write_of_the_session_and_on_demand(self):
        self.init()
        self.run_lua(READS)
        for i in range(3):
            self.raw_spawn(102 + 2 * i, 102)
            self.h.tick(1)
        self.assertEqual((self.seq(), self.ev('READS')), (3, 1))     # relue la première fois seulement
        self.raw_spawn(110, 102)
        self.assertTrue(self.ev('LivingKnox.Store.flush({ verify = true })'))
        self.assertEqual(self.ev('READS'), 2)
        self.assertTrue(self.ev('LivingKnox.Store.verifyFile()'))
        self.assertEqual(self.ev('READS'), 3)
        self.assertEqual(self.ev('LivingKnox.Store.stats.verified'), 3)
        # Fichier de la dernière écriture abîmé : la relecture sur demande bloque le registre.
        last = [f for f in self.registry_files() if f.name.endswith(f'-{self.seq() % 2}.txt')][0]
        last.write_text('garbage\n', encoding='utf-8')
        ok, why = self.run_lua('return LivingKnox.Store.verifyFile()')
        self.assertEqual((ok, why), (False, 'write verification failed'))
        self.assertTrue(self.ev('(LivingKnox.Store.isBlocked())'))


# Tri des clés de RS_Codec (LK13-T10) : comparateur historique reproduit ici, comparé octet pour octet.
LEGACY = r'''
local C = require "RadioSurvivor/RS_Codec"
local function pack(value, depth)
    local kind = type(value)
    if kind == 'boolean' then return value and 'b1' or 'b0' end
    if kind == 'string' then local s = C.toUtf8(value) return 's' .. #s .. ':' .. s end
    if kind == 'number' then local s = tostring(value) return 'n' .. #s .. ':' .. s end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    local out = {'t' .. #keys .. ':'}
    for _, k in ipairs(keys) do
        out[#out + 1] = pack(k, depth + 1)
        out[#out + 1] = pack(value[k], depth + 1)
    end
    return table.concat(out)
end
LEGACY_PACK = function(v) return pack(v, 0) end
'''


class CodecSortTests(Bench):
    def gen(self, rng, depth=0):
        """Table Lua (source) aux clés mêlées : chaînes, entiers, flottants, négatifs, clés qui se ressemblent."""
        parts = []
        used = set()
        for _ in range(rng.randint(0, 12)):
            r = rng.random()
            if r < 0.4:
                k = repr(rng.choice(['a', 'b', 'A', '1', '10', '2', 'n1', 'number1', 'x' * rng.randint(1, 4),
                                     'fort', 'members', 'z\\195\\169', '']) + str(rng.randint(0, 3)))
            elif r < 0.8:
                k = str(rng.randint(-20, 120))
            else:
                k = str(rng.choice([0.5, 1.25, -3.75, 1e15, 2.5e-3, 123456789012]))
            if k in used:
                continue
            used.add(k)
            if depth < 3 and rng.random() < 0.3:
                v = self.gen(rng, depth + 1)
            else:
                v = rng.choice(['true', 'false', str(rng.randint(-5, 5000)), '"v"', '1.5', '"\\226\\128\\153"'])
            parts.append(f'[{k}] = {v}')
        return '{ ' + ', '.join(parts) + ' }'

    def test_same_bytes_as_the_historical_comparator(self):
        self.run_lua(LEGACY)
        rng = random.Random(1310)
        for i in range(200):
            src = self.gen(rng)
            same = self.ev(f'(function() local C = require "RadioSurvivor/RS_Codec" local t = {src} '
                           f'return C.encodeBytes(t) == LEGACY_PACK(t) end)()')
            self.assertTrue(same, f'case {i}: {src}')

    def test_keys_printed_alike_keep_the_historical_order(self):
        self.run_lua(LEGACY)
        # Deux nombres distincts écrits pareil par tostring : possible sous Lua 5.1 (%.14g), jamais en Kahlua
        # (Double.toString, exact) ; simulé par un tostring qui arrondit. Repli sur le comparateur historique.
        same = self.ev('(function() local C = require "RadioSurvivor/RS_Codec" local orig = tostring '
                       'tostring = function(v) if type(v) == "number" and v > 0 and v < 1 then return "0.1" end '
                       'return orig(v) end '
                       'local t = { [0.1] = "a", [0.25] = "b", [0.5] = "c", x = 1, [2] = true } '
                       'local ok = C.encodeBytes(t) == LEGACY_PACK(t) tostring = orig return ok end)()')
        self.assertTrue(same)

    def test_registry_bytes_unchanged(self):
        self.run_lua(LEGACY)
        self.init()
        for i in range(4):
            self.raw_spawn(102 + 2 * i, 102)
        self.assertTrue(self.ev('(function() local C = require "RadioSurvivor/RS_Codec" local d = '
                                'LivingKnox.Store.data() return C.encodeBytes(d) == LEGACY_PACK(d) end)()'))


    def test_flat_encoder_same_bytes_on_large_and_repeated_tables(self):
        # LK13-T06 : tampon unique, clés et chaînes courtes mémorisées le temps d'un appel, tri par insertion
        # jusqu'à 12 clés puis table.sort : mêmes octets que le comparateur historique.
        self.run_lua(LEGACY)
        rng = random.Random(613)
        words = ['"hp"', '"x"', '"role"', '"name"', '"\\195\\169t\\195\\169"', '"' + 'w' * 70 + '"', '""']
        for i in range(60):
            members = []
            for m in range(rng.randint(0, 45)):
                fields = []
                for f in range(rng.randint(0, 30)):
                    k = rng.choice([str(f + 1), repr('k' + str(f)), str(rng.randint(-3, 40)), '0', '0.5'])
                    v = rng.choice(words + [str(rng.randint(-9, 9)), 'true', '{}', '{ 1, 2, 3 }'])
                    fields.append(f'[{k}] = {v}')
                members.append('{ ' + ', '.join(fields) + ' }')
            src = '{ ' + ', '.join(f'[{rng.choice([j + 1, j * 7 - 20])}] = {m}' for j, m in enumerate(members)) + ' }'
            same = self.ev(f'(function() local C = require "RadioSurvivor/RS_Codec" local t = {src} '
                           f'return C.encodeBytes(t) == LEGACY_PACK(t) end)()')
            self.assertTrue(same, f'case {i}')

    def test_flat_encoder_forced_utf16_and_depth_limit(self):
        self.run_lua(LEGACY)
        same = self.ev('(function() local C = require "RadioSurvivor/RS_Codec" '
                       'local t = { a = "\\195\\169", b = { a = "\\195\\169", ["\\195\\169"] = 1 } } '
                       'local plain = C.encodeBytes(t) C._utf16 = true local forced = C.encodeBytes(t) '
                       'local ok = forced == LEGACY_PACK(t) C._utf16 = nil '
                       'return ok and plain == LEGACY_PACK(t) and plain ~= forced end)()')
        self.assertTrue(same)
        # Profondeur : une feuille à la profondeur 12 passe, une table non vide à la profondeur 12 échoue (comme avant).
        depth = self.ev('(function() local C = require "RadioSurvivor/RS_Codec" '
                        'local function nest(n, leaf) local t = leaf for _ = 1, n do t = { t } end return t end '
                        'local ok1 = pcall(C.encodeBytes, nest(12, 1)) local ok2 = pcall(C.encodeBytes, nest(12, {})) '
                        'local ok3 = pcall(C.encodeBytes, nest(12, { 1 })) local ok4 = pcall(C.encodeBytes, { f = print }) '
                        'return tostring(ok1) .. tostring(ok2) .. tostring(ok3) .. tostring(ok4) end)()')
        self.assertEqual(depth, 'truetruefalsefalse')


    def test_fast_unhex_and_checksum_equal_the_codec(self):
        # LK13-T06 : relecture par table de remplacement et somme par seize octets : mêmes octets, mêmes refus.
        self.init()
        ok = self.ev('(function() local C = require "RadioSurvivor/RS_Codec" local St = LivingKnox.Store '
                     'math.randomseed(11) local ok = true '
                     'for n = 0, 80 do local t = {} for i = 1, n * 53 + (n % 17) do '
                     't[i] = string.char(math.random(0, 255)) end local s = table.concat(t) local h = C.hexBytes(s) '
                     'ok = ok and St.unhexOfBytes(h) == C.unhexBytes(h) and St.unhexOfBytes(h) == s '
                     'and St.checksumOfBytes(s) == C.checksumBytes(s) end '
                     'for _, bad in ipairs({ "abc", "AB", "0g", " 00", "00\\n" }) do '
                     'ok = ok and St.unhexOfBytes(bad) == nil and C.unhexBytes(bad) == nil end '
                     'return ok and St.unhexOfBytes(nil) == nil and St.unhexOfBytes("") == "" end)()')
        self.assertTrue(ok)


if __name__ == '__main__':
    unittest.main()
