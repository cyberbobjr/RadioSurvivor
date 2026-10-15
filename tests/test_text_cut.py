"""Découpe d'une réplique en morceaux affichés l'un après l'autre (E17-T12) : RS_TextCut.lua (Lua, lupa / Lua 5.1),
RS_GroupRadio.lines (réplique d'un PNJ de groupe à la radio) et radio_bridge.cut_pieces / radio_lines (pont, voix
radio).

    python RadioSurvivor/tests/test_text_cut.py

Constat du 2026-10-13 : une réplique longue venue du pont et dite par un PNJ arrivait coupée au milieu d'une phrase
(RS_GroupRadio.lines coupait au dernier espace avant 140 caractères ; le pont coupait une phrase de plus de 100
caractères entre deux mots). Vérifie : coupe à une fin de phrase, sinon à une virgule, sinon entre deux mots ; aucun
mot coupé ; accents et points de suspension ; « 9.5 » n'est pas une fin de phrase ; même découpe en Lua et en Python
sur un texte ASCII (sous Lua 5.1 la longueur est en octets ; dans la VM Kahlua réelle, en unités UTF-16 : égalité avec
Python vérifiée par tests/test_kahlua.py). Doublures : celles de RS_GroupRadio (fournisseur, fiches, transport) ne
servent qu'au chargement ; ne prouve pas l'affichage du récepteur en jeu (suite rs.groupradio).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
sys.path.insert(0, str(ROOT / 'bridge'))
import radio_bridge  # noqa: E402

ELLIPSIS = '…'
# Réplique longue réelle du 2026-10-13 (rs.npctalk), allongée : phrases, virgules, accents, décimal, points de
# suspension.
LONG = ("Oui, j'ai du travail pour toi. Il s'agit d'aller repérer une maison à West Point, une expédition de deux "
        "heures, avec 9.5 litres d'essence et un sac de toile bien rempli" + ELLIPSIS + " Le rapport se fait en "
        "personne et la récompense est de vingt cartouches de 9 mm. Est-ce que ça t'intéresse ?")
# Une seule phrase longue, avec des virgules : coupe aux virgules.
COMMAS = ("Nous avons marché depuis la rivière jusqu'au vieux silo, en évitant la grand-route, en dormant dans les "
          "granges abandonnées, en comptant nos balles une à une, sans jamais croiser âme qui vive avant ce matin")
# Une phrase sans ponctuation intérieure : coupe entre deux mots.
WORDS = ("nous avons marché depuis la rivière jusqu'au vieux silo en évitant la grand-route et en dormant dans les "
         "granges abandonnées sans jamais croiser âme qui vive")


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def ends_sentence(piece: str) -> bool:
    return piece.rstrip('"\')»')[-1:] in '.!?' + ELLIPSIS


def inner_sentence_end(piece: str) -> bool:
    """Vrai si le morceau contient une fin de phrase suivie d'un espace avant sa fin (coupe plus tôt possible)."""
    for i, ch in enumerate(piece[:-1]):
        if ch in '.!?' + ELLIPSIS:
            j = i + 1
            while j < len(piece) and piece[j] in '"\')»':
                j += 1
            if j < len(piece) and piece[j] == ' ':
                return True
    return False


class Checks:
    """Propriétés d'une découpe : longueur, mots entiers, texte complet, fin de phrase quand une existait."""

    def check(self, text, pieces, limit, measure=len, whole=True):
        self.assertTrue(pieces, 'no piece')
        for p in pieces:
            self.assertLessEqual(measure(p), limit, p)
            self.assertEqual(p, p.strip())
        if whole:
            self.assertEqual(' '.join(pieces), ' '.join(text.split()), 'words cut or lost')
        for p in pieces[:-1]:
            if not ends_sentence(p):
                self.assertFalse(inner_sentence_end(p), f'cut mid-sentence although a sentence end was possible: {p!r}')

    def pieces_of(self, text, limit):
        raise NotImplementedError

    def test_sentence_ends_first(self):
        pieces = self.pieces_of(LONG, 100)
        self.check(LONG, pieces, 100, self.measure)
        self.assertEqual(pieces[0], "Oui, j'ai du travail pour toi.")
        self.assertTrue(pieces[-1].endswith("intéresse ?"), pieces)
        self.assertIn('rempli' + ELLIPSIS, ' '.join(pieces))
        self.assertTrue(any(p.endswith('rempli' + ELLIPSIS) for p in pieces), pieces)  # points de suspension
        self.assertFalse(any(p.endswith('9.') for p in pieces), pieces)                 # 9.5 n'est pas une fin

    def test_short_sentences_grouped(self):
        text = 'Bonjour. Qui es-tu ? Que veux-tu ? Reste là.'
        self.assertEqual(self.pieces_of(text, 30), ['Bonjour. Qui es-tu ?', 'Que veux-tu ? Reste là.'])
        self.assertEqual(self.pieces_of(text, 100), [text])

    def test_commas_when_no_sentence_end(self):
        pieces = self.pieces_of(COMMAS, 80)
        self.check(COMMAS, pieces, 80, self.measure)
        self.assertGreater(len(pieces), 2)
        for p in pieces[:-1]:
            self.assertTrue(p.endswith(','), pieces)

    def test_words_when_no_punctuation(self):
        pieces = self.pieces_of(WORDS, 60)
        self.check(WORDS, pieces, 60, self.measure)
        words = set(WORDS.split())
        for p in pieces:
            for w in p.split():
                self.assertIn(w, words, f'word cut: {w!r}')

    def test_semicolon_and_colon_are_pauses(self):
        text = 'Il reste trois choses à faire ce soir; fermer la porte du fond: puis compter les boîtes de conserve'
        pieces = self.pieces_of(text, 50)
        self.check(text, pieces, 50, self.measure)
        self.assertTrue(pieces[0].endswith(';'), pieces)

    def test_detached_punctuation_stays_with_its_word(self):
        text = 'Tu veux vraiment venir avec nous jusque là-bas ? Alors suis-moi.'
        pieces = self.pieces_of(text, 50)
        self.assertEqual(pieces[0], 'Tu veux vraiment venir avec nous jusque là-bas ?')

    def test_word_longer_than_the_limit(self):
        pieces = self.pieces_of('abcdefghijklmnopqrstuvwxyz fin', 10)
        self.assertEqual(pieces, ['abcdefghij', 'klmnopqrst', 'uvwxyz fin'])

    def test_spaces_collapsed_and_empty(self):
        self.assertEqual(self.pieces_of('  a   b  ', 10), ['a b'])
        self.assertEqual(self.pieces_of('   ', 10), [])


class LuaTextCutTests(Checks, unittest.TestCase):
    """RS_TextCut.lua sous Lua 5.1 : longueurs en octets UTF-8."""

    @classmethod
    def setUpClass(cls):
        cls.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        cls.cut = cls.rt.execute((LUA / 'shared' / 'RadioSurvivor' / 'RS_TextCut.lua').read_text(encoding='utf-8'))

    @staticmethod
    def measure(p):
        return len(p.encode('utf-8'))

    def pieces_of(self, text, limit):
        return lua_list(self.cut.pieces(text, limit))

    def test_never_inside_a_character(self):
        # Mot de 12 « é » (24 octets) : coupe à 9 octets ramenée à 8 (jamais au milieu d'un caractère).
        pieces = self.pieces_of('é' * 12, 9)
        self.assertEqual(pieces, ['éééé', 'éééé', 'éééé'])

    def test_ends_sentence(self):
        self.assertTrue(self.cut.endsSentence('Il est là.'))
        self.assertTrue(self.cut.endsSentence('Il est là' + ELLIPSIS))
        self.assertTrue(self.cut.endsSentence('Il dit « oui ! »'.replace(' »', '»')))
        self.assertFalse(self.cut.endsSentence('Il est là,'))

    def test_same_cut_as_the_bridge_on_ascii(self):
        text = ('Yes, I have work for you. Go and scout a house in West Point, a two hours trip, with 9.5 litres of '
                'fuel and a full bag... Report in person; the reward is twenty 9 mm rounds. Interested?')
        for limit in (20, 37, 60, 100, 140):
            self.assertEqual(self.pieces_of(text, limit), radio_bridge.cut_pieces(text, limit), limit)


class BridgeTextCutTests(Checks, unittest.TestCase):
    """radio_bridge.cut_pieces : longueurs en caractères."""

    measure = staticmethod(len)

    def pieces_of(self, text, limit):
        return radio_bridge.cut_pieces(text, limit)

    def test_radio_lines_cut_at_sentence_ends(self):
        lines = radio_bridge.radio_lines(LONG)
        self.check(LONG, lines, radio_bridge.MAX_LINE_CHARS)
        self.assertTrue(all(ends_sentence(x) or x.endswith(',') for x in lines), lines)
        self.assertEqual(radio_bridge.radio_lines('  '), [radio_bridge.STATIC_LINE])


class GroupRadioLinesTests(unittest.TestCase):
    """RS_GroupRadio.lines (réplique d'un PNJ de groupe à l'antenne) : vrais RadioSurvivor_Const et RS_TextCut."""

    @classmethod
    def setUpClass(cls):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.execute('function isClient() return false end; function isServer() return false end')
        rt.globals().package.path = (str(LUA / 'shared') + '/?.lua;' + str(LUA / 'server') + '/?.lua;'
                                     + rt.globals().package.path)
        rt.execute('for _, m in ipairs({"RadioSurvivor/RS_Personas", "RadioSurvivor/RS_NPCProvider", '
                   '"RadioSurvivor/RS_Config", "RadioSurvivor/RS_Codec", "RadioSurvivor/RS_Transport"}) do '
                   'package.preload[m] = function() return {} end end')
        cls.const = rt.eval('require("RadioSurvivor/RadioSurvivor_Const")')
        cls.radio = rt.eval('require("RadioSurvivor/RS_GroupRadio")')

    def test_long_reply_cut_at_sentence_ends(self):
        text = LONG + ' ' + LONG
        lines = lua_list(self.radio.lines(text))
        limit = self.const.MAX_LINE_CHARS
        self.assertLessEqual(len(lines), self.const.MAX_LINES - 1)
        for x in lines:
            self.assertLessEqual(len(x.encode('utf-8')), limit)
        for x in lines[:-1]:
            self.assertTrue(ends_sentence(x) or not inner_sentence_end(x), lines)
        self.assertTrue(ends_sentence(lines[0]), lines)
        self.assertTrue(' '.join(text.split()).startswith(' '.join(lines)), 'words cut or lost')

    def test_markup_removed(self):
        self.assertEqual(lua_list(self.radio.lines('a <b> c')), ['a b c'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
