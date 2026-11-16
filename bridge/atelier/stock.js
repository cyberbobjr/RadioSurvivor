// Registry of the section forms (E22-T12, user 2026-11-15), read by sectionform.js: KEY_EDITORS[section kind][key] is
// the form of a key (a key missing here keeps the plain field or list of lines of the grammar), KEY_GROUPS[kind] the
// questions a player answers in order, each with the keys it holds (E24-T02, charter rule 4: one question at a time;
// the keys of no group follow). The forms live with their section: tradekeys.js ([trade]) and notekeys.js ([note]); an
// own [category] lists its items like the trader's stock.

import { NOTE_EDITORS } from './notekeys.js';
import { stockItems, TRADE_EDITORS } from './tradekeys.js';

export const KEY_EDITORS = {
  trade: TRADE_EDITORS,
  note: NOTE_EDITORS,
  category: { item: stockItems },
};

// kind -> [{title: i18n key or null, keys: [...]}].
export const KEY_GROUPS = {
  trade: [
    { title: 'trade.q_sell', keys: ['item', 'group'] },
    { title: 'trade.q_meet', keys: ['landing', 'arrival', 'hours', 'every_days', 'delay_hours'] },
    { title: 'trade.q_pay', keys: ['accept', 'margin'] },
  ],
  note: [
    { title: null, keys: ['text'] },
    { title: 'note.q_also', keys: ['loot', 'glovebox'] },   // E24-T03: themed places on top of the common base
  ],
};

// Action a section needs in the head `actions=` (the game refuses a [trade] without propose_trade): ticked with it.
export const SECTION_ACTIONS = { trade: 'propose_trade' };

export const SECTION_FORMS = { editors: KEY_EDITORS, groups: KEY_GROUPS };
