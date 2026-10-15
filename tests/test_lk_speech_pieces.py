"""Réplique longue d'un PNJ en bulle lue en phrases entières (E17-T13) : LK_SpeechView.lua (bulle découpée en morceaux
successifs par RS_TextCut.pieces) et bridge/npc_protocol.py (clean_speech : coupe d'une réplique trop longue, consigne
de longueur au modèle).

    python RadioSurvivor/tests/test_lk_speech_pieces.py

Constat du 2026-10-14 : des répliques de PNJ se lisaient coupées au milieu d'une phrase dans les bulles. Chemins
prouvés (ancien code) :
- pont, clean_speech (npc_protocol.py) : une réplique plus longue que sa limite (200 octets pour une conversation entre
  PNJ, une initiative, une réaction de membre ; 1600 pour une réponse au joueur) était coupée au dernier mot avec
  « ... » dès que sa dernière fin de phrase tombait dans le premier tiers : « Oui. Je les ai vus passer ... de la
  nuit... » ; la consigne au modèle comptait en octets (« 200 bytes »), que le modèle ne compte pas ;
- bulle, View.show : une réponse au joueur (jusqu'à 1600 octets) dans une seule bulle de 15 s au plus, quelle que soit
  sa longueur, et une réplique suivante du même corps remplaçait la bulle avant qu'elle ait été lue.
Doublures : celles de test_lk_speech.py (banc solo, dessin noté) ; ne prouvent pas le rendu en jeu (suite rs.npctalk).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_speech import SpeechBase, lua_str  # noqa: E402
from test_text_cut import ELLIPSIS, ends_sentence, inner_sentence_end  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol as protocol  # noqa: E402

# Réponse longue au joueur (ASCII : longueurs identiques en octets sous Lua 5.1 et en caractères).
ANSWER = ("I have been walking since the river with my brother, and we slept in barns along the old road. "
          "Last night three armed men passed near the silo with full bags; they laughed and went north. "
          "We hid in the hay until dawn, then we came here because the church still had a roof. "
          "If you want to help, bring bandages and clean water. We will share what we find in the houses around. "
          "Do not go near the silo after dark.")


class BubblePiecesTests(SpeechBase):
    """Bulle (LK11-T09) : un texte long en morceaux successifs, chacun une ou plusieurs phrases entières."""
    mode = 'solo'

    def setUp(self):
        super().setUp()
        self.init()
        self.spawn(102, 102)

    def shown_text(self):
        """Texte de la bulle dessinée à cette image (lignes de haut en bas), ou None."""
        self.h.load('solo', 'DRAWS = {}')
        self.h.fire('solo', 'OnPreUIDraw')
        n = self.h.eval('solo', '#DRAWS')
        lines = [self.h.eval('solo', f'DRAWS[{i}]') for i in range(1, n + 1)]
        texts = [d.text for d in lines if d.r != 0 or d.g != 0 or d.b != 0]
        return ' '.join(reversed(texts)) if texts else None

    def show(self, text):
        return self.v(f'show(LivingKnox.Bodies.find("lk-1"), {lua_str(text)})', 'solo')

    def read_all(self):
        """Morceaux affichés l'un après l'autre jusqu'à la fin de la bulle, avec la durée de chacun."""
        seen = []
        for _ in range(40):
            text = self.shown_text()
            if text is None:
                return seen
            ms = self.v('bubbles[1].ms', 'solo')
            self.assertEqual(self.v('bubbles[1].untilMs - LivingKnox.SpeechView.bubbles[1].born', 'solo'), ms)
            seen.append((text, ms))
            left = self.v('bubbles[1].untilMs', 'solo') - self.h.eval('solo', 'getTimestampMs()')
            self.h.advance_ms(left - 1)
            self.assertEqual(self.shown_text(), text, 'piece replaced before its reading time')
            self.h.advance_ms(1)
        self.fail('bubble never ends')

    def test_long_answer_read_in_whole_sentences_one_piece_after_another(self):
        self.assertTrue(self.show(ANSWER))
        seen = self.read_all()
        pieces = [p for p, _ in seen]
        limit = self.v('PIECE', 'solo')
        self.assertGreater(len(pieces), 2, pieces)                       # ancien code : une seule bulle
        self.assertEqual(' '.join(pieces), ANSWER, 'words cut or lost')
        for p, ms in seen:
            self.assertLessEqual(len(p), limit, p)
            self.assertTrue(ends_sentence(p), f'piece does not end a sentence: {p!r}')
            self.assertEqual(ms, min(5000 + 60 * len(p), 15000))         # durée de lecture propre au morceau
        log = self.v('pieceLog', 'solo')
        self.assertEqual([log[i].text for i in range(1, len(log) + 1)], pieces)
        self.assertEqual(self.v('lastPieces.text', 'solo'), ANSWER)

    def test_notebook_answer_goes_through_the_same_pieces(self):
        self.h.load('solo', 'shared/RadioSurvivor/RS_NPCProvider.lua')
        self.h.load('solo', 'shared/RadioSurvivor/RS_LivingKnox.lua')
        self.run_lua(f'RS_LivingKnox.bubble(LivingKnox.Bodies.find("lk-1"), {lua_str(ANSWER)}, 25)')
        pieces = [p for p, _ in self.read_all()]
        self.assertGreater(len(pieces), 2, pieces)
        self.assertTrue(all(ends_sentence(p) for p in pieces), pieces)

    def test_next_text_waits_until_the_bubble_was_read(self):
        self.assertIsNotNone(self.ev('LivingKnox.Speech.say("lk-1", "Stay where you are.")'))
        self.h.advance_ms(1000)
        self.assertTrue(self.show('Who goes there?'))                   # ancien code : bulle remplacée aussitôt
        self.assertEqual([p for p, _ in self.read_all()], ['Stay where you are.', 'Who goes there?'])

    def test_one_long_sentence_cut_at_commas_never_inside_a_word(self):
        text = ', '.join(['we walked from the river to the old silo'] * 8) + '.'
        self.assertTrue(self.show(text))
        pieces = [p for p, _ in self.read_all()]
        self.assertEqual(' '.join(pieces), text)
        for p in pieces[:-1]:
            self.assertTrue(p.endswith(','), pieces)
            self.assertFalse(inner_sentence_end(p), p)

    def test_waiting_pieces_bounded(self):
        self.h.load('solo', 'LivingKnox.SpeechView.MAX_PIECES = 3')
        self.assertTrue(self.show(ANSWER))
        self.assertTrue(self.show(ANSWER))
        self.assertEqual(self.h.eval('solo', '#LivingKnox.SpeechView.bubbles[1].rest'), 3)
        self.assertGreater(self.v('stats.dropped', 'solo'), 0)

    def test_dead_body_drops_its_waiting_pieces(self):
        self.assertTrue(self.show(ANSWER))
        self.run_lua('LivingKnox.Bodies.find("lk-1").square = nil')
        self.assertIsNone(self.shown_text())
        self.assertEqual(self.h.eval('solo', '#LivingKnox.SpeechView.bubbles'), 0)


class CleanSpeechTests(unittest.TestCase):
    """Pont : réplique trop longue coupée à une fin de phrase, même courte ; consigne de longueur en caractères."""

    def test_short_first_sentence_kept_rather_than_a_cut_sentence(self):
        text = ("Oui. Je les ai vus passer près du vieux silo hier soir, trois hommes armés qui portaient des sacs "
                "pleins, et ils parlaient de revenir chercher le reste des provisions avant la tombée de la nuit, "
                "alors méfie-toi.")
        self.assertGreater(len(text.encode('utf-8')), 200)
        self.assertEqual(protocol.clean_speech(text, 200), 'Oui.')     # ancien code : « ... de la nuit... »

    def test_last_sentence_end_that_fits(self):
        text = 'Je ne sais pas. ' * 3 + 'Mais ' + 'très ' * 40
        out = protocol.clean_speech(text, 200)
        self.assertEqual(out, 'Je ne sais pas. Je ne sais pas. Je ne sais pas.')   # ancien code : « très très... »

    def test_sentence_end_before_closing_quote_and_ellipsis(self):
        text = 'Il m’a dit : « Pars. » Puis il est parti' + ELLIPSIS + ' ' + 'loin ' * 60
        out = protocol.clean_speech(text, 120)
        self.assertEqual(out, 'Il m’a dit : « Pars. » Puis il est parti' + ELLIPSIS)
        self.assertLessEqual(len(out.encode('utf-8')), 120)

    def test_no_sentence_end_comma_then_word_with_dots(self):
        commas = 'nous avons marché longtemps, ' * 12
        out = protocol.clean_speech(commas, 100)
        self.assertTrue(out.endswith('longtemps...'), out)
        self.assertLessEqual(len(out.encode('utf-8')), 100)
        words = protocol.clean_speech('très ' * 400, protocol.MAX_REPLY_BYTES)
        self.assertTrue(words.endswith('très...'), words[-20:])
        self.assertLessEqual(len(words.encode('utf-8')), protocol.MAX_REPLY_BYTES)

    def test_every_cut_within_the_byte_limit_and_whole_words(self):
        base = ("Oui, j'ai du travail pour toi. Il s'agit d'aller repérer une maison à West Point, une expédition "
                "de deux heures. Est-ce que ça t'intéresse ? Réponds vite" + ELLIPSIS + " ")
        text = base * 6
        words = set(text.split())
        for limit in range(40, 400, 7):
            out = protocol.clean_speech(text, limit)
            self.assertLessEqual(len(out.encode('utf-8')), limit)
            self.assertTrue(ends_sentence(out), (limit, out))
            for w in out.split():
                self.assertIn(w, words, (limit, out))

    def test_prompts_ask_characters_not_bytes(self):
        rule = protocol.spoken_limit(200)
        self.assertEqual(rule, 'at most two short sentences, under 150 characters in all')
        sources = (Path(protocol.__file__)).read_text(encoding='utf-8')
        self.assertNotIn('bytes, no stage', sources)
        self.assertNotIn('REPLY_BYTES} bytes', sources)
        for name in ('MEMBER_REPLY_BYTES', 'CONVERSE_REPLY_BYTES', 'INITIATIVE_REPLY_BYTES'):
            self.assertIn(f'spoken_limit({name})', sources)

    def test_bridge_alias(self):
        sys.path.insert(0, str(ROOT / 'bridge'))
        import radio_bridge
        self.assertIs(radio_bridge.cut_pieces, protocol.cut_pieces)


if __name__ == '__main__':
    unittest.main(verbosity=2)
