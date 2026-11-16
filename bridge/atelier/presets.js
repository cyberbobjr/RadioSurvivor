// Voice types of a new voice (E24-T02 user decision): a card "Survivor who talks", "Mission giver" or "Trader" ticks the
// actions that go with it and adds the sections it needs; the steps a voice does not use are folded (shown again by
// "All steps", or as soon as an action or a section needs them). Nothing is stored about the type: the sheet's actions
// and sections decide which steps a voice wants, so every choice can be changed later. Pure module.

import * as sheet from './sheet.js';
import { formatList, parseList } from './values.js';

// id -> the actions ticked (say always first) and the sections added. i18n: newtype.<id>, .help, .icon.
export const VOICE_TYPES = [
  { id: 'talker', actions: ['say'], sections: [] },
  { id: 'missions', actions: ['say', 'start_mission'], sections: [] },
  { id: 'trader', actions: ['say', 'propose_trade'], sections: ['trade'] },
];

// Steps a voice may not need (step id -> what makes it wanted: one of these actions, or a section of these kinds).
// A step missing here is always shown.
export const STEP_WANTS = {
  missions: { actions: ['start_mission', 'propose_trade', 'mark_map', 'reveal_area'], blocks: ['place', 'mission'] },
  rewards: { actions: ['start_mission', 'propose_trade'], blocks: ['rewards', 'trade', 'note', 'category'] },
};

export function applyVoiceType(model, typeId) {
  const type = VOICE_TYPES.find((v) => v.id === typeId);
  if (!type) return;
  sheet.setValue(model.head, 'actions', formatList(type.actions));
  for (const kind of type.sections) if (!sheet.section(model, kind)) sheet.addSection(model, kind);
}

// Whether a voice wants a step (`wants` of STEP_WANTS, undefined: always).
export function stepWanted(wants, model) {
  if (!wants) return true;
  const actions = parseList(sheet.value(model.head, 'actions'));
  return wants.actions.some((a) => actions.includes(a)) || wants.blocks.some((kind) => sheet.sectionsOf(model, kind).length > 0);
}
