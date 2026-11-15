// Forms of the [note] keys (E22-T07, E22-T12, user 2026-11-15): the text written on the note (text=, one line each,
// live count of the game's limit, %1 = the voice's frequency), where it is found (loot= and glovebox=, a list of the
// game and Rarely / Normally / Often) and the corpses switch (corpse=yes). The note's own item and text key (item=,
// key=, shipped voices only) stay in the advanced settings of the form (sectionform.js ADVANCED). Registered in
// stock.js KEY_EDITORS.

import { h, uid } from './dom.js';
import { ADVANCED } from './sectionform.js';
import * as sheet from './sheet.js';
import { DEFAULT_CHANCE, formatLootList, parseLootList, utf8Bytes } from './values.js';
import { button, chanceChoice, lineEditor, removeButton, switchBox } from './widgets.js';

// Limits of a note text line, as RS_Persona.lua reads them (MAX_NOTE_LINES, MAX_NOTE_LINE_BYTES, writtenText): the
// catalogue grammar does not carry them.
const MAX_LINES = 8;
const MAX_BYTES = 40;
const FREQUENCY = '%1';
const OWN_ITEM_KEYS = ['item', 'key'];
const badText = (text) => /[<>^]/.test(text) || text.split(FREQUENCY).join('').includes('%');

// Suggestions of a text field: a <datalist> with an id, placed next to the field.
function datalist(values) {
  return h('datalist', { id: uid('dl') }, [...new Set(values)].filter(Boolean).sort().map((v) => h('option', { value: v })));
}

// Text of the note: up to MAX_LINES lines, each with its count of bytes (an accented letter takes two).
function noteText(ctx, section, key) {
  const { t, changed } = ctx;
  if (!sheet.values(section, key).length && OWN_ITEM_KEYS.some((k) => sheet.values(section, k).length)) {
    return h('p', { class: 'muted', text: t('note.own_item') });
  }
  const lines = sheet.values(section, key);
  if (!lines.length) lines.push('');
  const box = h('div', { class: 'stack note-text' });
  const missing = h('p', { class: 'warnline' });
  const showMissing = () => {
    missing.textContent = lines.some((l) => l.includes(FREQUENCY)) ? '' : t('note.needs_frequency');
  };
  const write = () => { sheet.setValues(section, key, lines); changed(); showMissing(); };
  const lineRow = (index) => {
    const counter = h('span', { class: 'counter', 'aria-live': 'polite' });
    const warn = h('span', { class: 'warnline' });
    const update = () => {
      const n = utf8Bytes(lines[index]);
      counter.textContent = t('note.bytes', { n, max: MAX_BYTES });
      counter.classList.toggle('over', n > MAX_BYTES);
      if (n > MAX_BYTES) warn.textContent = t('note.too_long', { max: MAX_BYTES });
      else warn.textContent = badText(lines[index]) ? t('note.bad_chars') : '';
    };
    const input = h('input', { type: 'text', value: lines[index], placeholder: t('key.note.text.placeholder'),
      'aria-label': t('note.line', { n: index + 1 }), onInput: (e) => { lines[index] = e.target.value; update(); write(); } });
    update();
    return h('div', { class: 'note-line' },
      h('div', { class: 'inline grow' }, input, counter,
        removeButton(t, () => { lines.splice(index, 1); write(); draw(); })),
      warn);
  };
  const draw = (focus = -1) => {
    box.replaceChildren(h('p', { class: 'help', text: t('note.text_intro') }),
      ...lines.map((_, index) => lineRow(index)),
      h('div', {}, button('add', { disabled: lines.length >= MAX_LINES,
        onClick: () => { lines.push(''); draw(lines.length - 1); } }, t('note.add_line'))),
      missing);
    showMissing();
    if (focus >= 0) box.querySelectorAll('.note-line input')[focus]?.focus();
  };
  draw();
  return box;
}

// Loot lists (loot=, glovebox=): a list of the game (suggested from the catalogue and the other notes) and how often.
function lootLists(ctx, section, key) {
  const { t, catalog, model, changed } = ctx;
  const known = datalist([...catalog.lootLists(key),
    ...sheet.sectionsOf(model, 'note').flatMap((s) => sheet.values(s, key).map((v) => parseLootList(v).list))]);
  const write = (items) => { sheet.setValues(section, key, items.map(formatLootList)); changed(); };
  return h('div', { class: 'stack' }, known, lineEditor(t, sheet.values(section, key).map(parseLootList), {
    addLabel: t('stock.add_list'),
    blank: () => ({ list: '', weight: DEFAULT_CHANCE }),
    write,
    draw: (item, index, change) => h('div', { class: 'line-fields loot-line' },
      h('input', { type: 'text', value: item.list, list: known.id, spellcheck: 'false',
        placeholder: t(`key.note.${key}.placeholder`), 'aria-label': t('stock.list', { n: index + 1 }),
        onInput: (e) => { item.list = e.target.value; change(); } }),
      chanceChoice(t, item.weight, (v) => { item.weight = v; change(); }, { 'aria-label': t('stock.chance') })),
  }));
}

// corpse=yes, or no line (the game's default: no).
function corpse(ctx, section, key) {
  const { t, changed } = ctx;
  return switchBox(t('note.corpse_switch'), sheet.value(section, key) === 'yes', (on) => {
    sheet.setValue(section, key, on ? 'yes' : null);
    changed();
  });
}

export const NOTE_EDITORS = {
  text: noteText,
  loot: lootLists,
  glovebox: lootLists,
  corpse,
  item: ADVANCED,
  key: ADVANCED,
};
