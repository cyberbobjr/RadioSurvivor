// Registry of the section forms (E22-T12, user 2026-11-15), read by sectionform.js: KEY_EDITORS[section kind][key] is
// the form of a key (a key missing here keeps the plain field or list of lines of the grammar), KEY_ORDER[kind] the
// order a player fills the keys in (the others follow). The forms live with their section: tradekeys.js ([trade]) and
// notekeys.js ([note]); an own [category] lists its items like the trader's stock.

import { NOTE_EDITORS } from './notekeys.js';
import { stockItems, TRADE_EDITORS } from './tradekeys.js';

export const KEY_EDITORS = {
  trade: TRADE_EDITORS,
  note: NOTE_EDITORS,
  category: { item: stockItems },
};

export const KEY_ORDER = {
  trade: ['landing', 'arrival', 'hours', 'every_days', 'item', 'group', 'accept', 'margin', 'delay_hours'],
  note: ['text', 'loot', 'glovebox', 'corpse'],
};

// Action a section needs in the head `actions=` (the game refuses a [trade] without propose_trade): ticked with it.
export const SECTION_ACTIONS = { trade: 'propose_trade' };

export const SECTION_FORMS = { editors: KEY_EDITORS, order: KEY_ORDER };
