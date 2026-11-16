"""E24-T02: nothing technical to type in the voice workshop (bridge/atelier, charter docs/annexes/conception/charte-atelier.md).

    python RadioSurvivor/tests/test_atelier_simple.py

The pure ES modules run in node (skipped when node is missing):
- voice ids made from the first name, unique among the voices (voice.js);
- named steps of the numeric settings (scales.js): a step writes its value, a hand-written value shows its nearest step;
- the trader's margin as three cards (Generous, Fair, Greedy) over the margin= ranges of the format;
- the story state written as a sentence (story.js): a deterministic name made from it, collisions handled, and the
  sentence kept in the personality text where the AI reads it;
- the voice-type cards of a new voice (presets.js): the actions they tick and the steps they fold;
- the paquets of a trader (group=): an id made from the name typed, its items kept with it when renamed.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_atelier_ui import NODE, module_url, node_prelude, run_node  # noqa: E402


def prelude() -> str:
    return node_prelude() + (f"import * as scales from '{module_url('scales.js')}';\n"
                             f"import * as story from '{module_url('story.js')}';\n"
                             f"import * as presets from '{module_url('presets.js')}';\n"
                             f"import * as paquets from '{module_url('paquets.js')}';\n")


@unittest.skipUnless(NODE, 'node is not installed')
class AtelierSimpleTests(unittest.TestCase):
    def test_voice_id_is_made_from_the_first_name_and_unique(self):
        got = run_node(prelude() + """
console.log(JSON.stringify([
  voice.voiceId('Mae Tolliver', []), voice.voiceId('Mae Tolliver', ['mae']), voice.voiceId('Mae Tolliver', ['mae', 'mae_2']),
  voice.voiceId('Élodie', []), voice.voiceId('  ', []), voice.voiceId('42 Joe', []),
]));
""")
        self.assertEqual(got, ['mae', 'mae_2', 'mae_3', 'elodie', 'voice', 'voice_42'])

    def test_named_steps_write_their_value_and_show_the_nearest_step(self):
        got = run_node(prelude() + """
const call = scales.SCALES['scale.head.call_one_in'];
const days = scales.SCALES['scale.trade.every_days'];
const delay = scales.SCALES['scale.trade.delay_hours'];
const at = (scale, text) => { const s = scales.stepOf(scale, text); return s && [s.step.id, s.exact]; };
console.log(JSON.stringify({
  call: [null, '', '0', '3', '6', '12', '8', '1000'].map((v) => at(call, v)),
  days: ['7', '4', '28', ''].map((v) => at(days, v)),
  delay: [null, '2', '0', '30'].map((v) => at(delay, v)),
  never: call.steps.find((s) => s.id === 'never').value,
  every: Object.keys(scales.SCALES).every((k) => scales.SCALES[k].steps.length >= 3),
}));
""")
        self.assertEqual(got['call'][:3], [['never', True], ['never', True], ['never', True]])
        self.assertEqual(got['call'][3:6], [['often', True], ['sometimes', True], ['rare', True]])
        self.assertEqual(got['call'][6], ['sometimes', False], 'one chance in 8: nearest step "sometimes" (6)')
        self.assertEqual(got['call'][7], ['rare', False])
        self.assertEqual(got['days'], [['weekly', True], ['few_days', False], ['monthly', True], None])
        self.assertEqual(got['delay'], [['hour', True], ['hour', False], ['now', True], ['day', False]])
        self.assertIsNone(got['never'], 'never: no call_one_in line')
        self.assertTrue(got['every'])

    def test_margin_cards_cover_the_ranges_of_the_format(self):
        got = run_node(prelude() + """
const margin = scales.SCALES['scale.trade.margin'];
const at = (text) => { const s = scales.stepOf(margin, text); return [s.step.id, s.exact]; };
console.log(JSON.stringify({
  ids: margin.steps.map((s) => s.id), values: margin.steps.map((s) => s.value),
  read: [null, '0.10-0.50', '0.05-0.25', '0.30-0.80', '0.20-0.60', '0.00-0.10'].map(at),
}));
""")
        self.assertEqual(got['ids'], ['generous', 'fair', 'greedy'])
        self.assertEqual(got['values'], ['0.05-0.25', None, '0.30-0.80'], 'Fair: no line, the game default 0.10-0.50')
        self.assertEqual(got['read'], [['fair', True], ['fair', True], ['generous', True], ['greedy', True],
                                       ['fair', False], ['generous', False]])

    def test_story_state_sentence_makes_a_hidden_name_read_by_the_ai(self):
        got = run_node(prelude() + """
const model = voice.newVoice({ id: 'mae', name: 'Mae', radio: 'any_talkie' });
const [a, b, c] = ['scout', 'clear', 'watch'].map((type) => voice.addMission(model, type));
story.setStory(model, a, 'Elle est rentrée à sa clinique');
story.setStory(model, b, 'Elle est rentrée à sa clinique');       // same sentence: same state
story.setStory(model, c, 'Elle est rentree a sa clinique !');     // same name, other sentence: another state
const before = sheet.promptText(model);
const states = [a, b, c].map((m) => sheet.value(m, 'sets_state'));
const sentences = [a, b, c].map((m) => story.sentence(model, m));
story.setStory(model, c, '');
const cleared = [sheet.value(c, 'sets_state'), story.lines(sheet.promptText(model))];
story.setStory(model, a, 'Elle a fui');
const moved = [sheet.value(a, 'sets_state'), sheet.value(b, 'sets_state'), story.lines(sheet.promptText(model))];
const darlene = sheet.parse('format=1\\nid=d\\nname=D\\n\\n[mission m]\\ntype=scout\\nsets_state=returned\\n\\n[prompt]\\nYou are D.\\n');
console.log(JSON.stringify({ states, sentences, before, cleared, moved,
  handWritten: story.sentence(darlene, voice.missions(darlene)[0]),
  long: story.slugOf('Une phrase vraiment beaucoup trop longue pour un nom de trente-deux lettres'),
  same: story.slugOf('Elle est rentrée à sa clinique') === story.slugOf('Elle est rentrée à sa clinique') }));
""")
        self.assertEqual(got['states'], ['elle_est_rentree_a_sa_clinique', 'elle_est_rentree_a_sa_clinique',
                                         'elle_est_rentree_a_sa_clinique_2'])
        self.assertEqual(got['sentences'], ['Elle est rentrée à sa clinique', 'Elle est rentrée à sa clinique',
                                            'Elle est rentree a sa clinique !'])
        self.assertIn('Story state: when your story state is elle_est_rentree_a_sa_clinique, '
                      'Elle est rentrée à sa clinique', got['before'])
        self.assertIn('Story state: when your story state is elle_est_rentree_a_sa_clinique_2, '
                      'Elle est rentree a sa clinique !', got['before'])
        self.assertTrue(got['before'].startswith('You are Mae'), 'the personality text stays first')
        self.assertIsNone(got['cleared'][0])
        self.assertEqual(got['cleared'][1], {'elle_est_rentree_a_sa_clinique': 'Elle est rentrée à sa clinique'})
        self.assertEqual(got['moved'][:2], ['elle_a_fui', 'elle_est_rentree_a_sa_clinique'])
        self.assertEqual(got['moved'][2], {'elle_est_rentree_a_sa_clinique': 'Elle est rentrée à sa clinique',
                                           'elle_a_fui': 'Elle a fui'}, 'a state still used by a mission keeps its line')
        self.assertEqual(got['handWritten'], 'returned', 'a state written by hand shows as its words')
        self.assertLessEqual(len(got['long']), 32)
        self.assertRegex(got['long'], r'^[a-z][a-z0-9_]*$')
        self.assertTrue(got['same'])

    def test_a_new_personality_text_keeps_the_story_lines(self):
        """The AI's personality (or any text put in its place by the page) keeps the story lines of the old text."""
        got = run_node(prelude() + """
const old = 'You are Mae.\\n\\nStory state: when your story state is home, She went home';
console.log(JSON.stringify([story.carry(old, 'You are Mae, 67.'),
  story.carry(old, 'You are Mae.\\n\\nStory state: when your story state is home, She went home')]));
""")
        self.assertEqual(got[0], 'You are Mae, 67.\n\nStory state: when your story state is home, She went home')
        self.assertEqual(got[1], 'You are Mae.\n\nStory state: when your story state is home, She went home')

    def test_voice_type_cards_tick_their_actions_and_fold_the_other_steps(self):
        got = run_node(prelude() + """
const out = {};
for (const type of presets.VOICE_TYPES) {
  const model = voice.newVoice({ id: 'v', name: 'V', radio: 'any_talkie' });
  presets.applyVoiceType(model, type.id);
  out[type.id] = { actions: sheet.value(model.head, 'actions'), trade: Boolean(sheet.section(model, 'trade')),
    steps: ['missions', 'rewards'].filter((s) => presets.stepWanted(presets.STEP_WANTS[s], model)) };
}
const later = voice.newVoice({ id: 'v', name: 'V', radio: 'any_talkie' });
presets.applyVoiceType(later, 'talker');
sheet.setValue(later.head, 'actions', 'say,start_mission');
out.later = ['missions', 'rewards'].filter((s) => presets.stepWanted(presets.STEP_WANTS[s], later));
console.log(JSON.stringify(out));
""")
        self.assertEqual(got['talker'], {'actions': 'say', 'trade': False, 'steps': []})
        self.assertEqual(got['missions'], {'actions': 'say,start_mission', 'trade': False,
                                           'steps': ['missions', 'rewards']})
        self.assertEqual(got['trader'], {'actions': 'say,propose_trade', 'trade': True, 'steps': ['missions', 'rewards']})
        self.assertEqual(got['later'], ['missions', 'rewards'], 'a step comes back once its action is ticked')

    def test_paquet_id_is_made_from_its_name_and_its_items_follow_a_rename(self):
        got = run_node(prelude() + """
const model = sheet.parse('format=1\\nid=b\\nname=B\\n\\n[trade]\\nitem=Base.Rice:2-4\\n');
const trade = sheet.section(model, 'trade');
const seeds = paquets.addPaquet(trade, 'Graines');
const again = paquets.addPaquet(trade, 'graines!');
paquets.addItems(trade, seeds, ['Base.CarrotSeed', 'Base.TomatoSeed']);
paquets.setTotal(trade, seeds, '2-5');
paquets.setKinds(trade, seeds, '3');
const renamed = paquets.rename(trade, seeds, 'Médicaments');
console.log(JSON.stringify({ seeds, again, renamed, groups: sheet.values(trade, 'group'), items: sheet.values(trade, 'item'),
  list: paquets.list(trade).map((p) => [p.id, p.label, p.items]), loose: paquets.looseItems(trade).map((l) => l.type) }));
""")
        self.assertEqual([got['seeds'], got['again'], got['renamed']], ['graines', 'graines_2', 'medicaments'])
        self.assertEqual(got['groups'], ['medicaments:2-5:3', 'graines_2:1-3'])
        self.assertEqual(got['items'], ['Base.Rice:2-4', 'Base.CarrotSeed:medicaments', 'Base.TomatoSeed:medicaments'])
        self.assertEqual(got['list'], [['medicaments', 'Medicaments', ['Base.CarrotSeed', 'Base.TomatoSeed']],
                                       ['graines_2', 'Graines 2', []]])
        self.assertEqual(got['loose'], ['Base.Rice'])


if __name__ == '__main__':
    unittest.main()
