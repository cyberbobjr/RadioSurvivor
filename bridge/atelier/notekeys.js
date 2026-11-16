// Forms of the [note] keys (E22-T07, E22-T12, user 2026-11-15): the text written on the note (text=, one line each,
// live count of the game's limit, %1 = the voice's frequency), where it is found (loot= and glovebox=, a list of the
// game and Rarely / Normally / Often) and the corpses switch (corpse=yes). The note's own item and text key (item=,
// key=, shipped voices only) stay in the advanced settings of the form (sectionform.js advanced), the item picked in the
// item browser like every item of the page. Registered in stock.js KEY_EDITORS.

import { h, uid } from './dom.js';
import { itemChoice } from './itempicker.js';
import { ADVANCED, advanced } from './sectionform.js';
import * as sheet from './sheet.js';
import { DEFAULT_CHANCE, FREQUENCY_MARK, formatLootList, parseLootList, utf8Bytes } from './values.js';
import { button, chanceChoice, freqText, lineEditor, removeButton, switchBox } from './widgets.js';

// Limits of a note text line, as RS_Persona.lua reads them (MAX_NOTE_LINES, MAX_NOTE_LINE_BYTES, writtenText): the
// catalogue grammar does not carry them.
const MAX_LINES = 8;
const MAX_BYTES = 40;
const FREQUENCY = FREQUENCY_MARK;
const OWN_ITEM_KEYS = ['item', 'key'];
const badText = (text) => /[<>^]/.test(text) || text.split(FREQUENCY).join('').includes('%');

// A loot list of the game in words: "MedicalOfficeDesk" -> "Medical office desk" (charter rule 1: the game's name only in
// the tooltip).
export function lootLabel(name) {
  const words = String(name ?? '').replace(/_/g, ' ').replace(/([a-z0-9])([A-Z])/g, '$1 $2').trim().toLowerCase();
  return words ? words[0].toUpperCase() + words.slice(1) : '';
}

// Suggestions of a list field: a <datalist> of plain names, with the map back to the game's names.
function datalist(values) {
  const names = new Map([...new Set(values)].filter(Boolean).map((v) => [lootLabel(v), v]));
  const el = h('datalist', { id: uid('dl') }, [...names.keys()].sort().map((v) => h('option', { value: v })));
  return { el, nameOf: (label) => names.get(label.trim()) ?? label.trim() };
}

// Text of the note: up to MAX_LINES lines, each with its count (the game counts bytes: an accented letter takes two),
// the frequency shown as a word and put in by a button.
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
    const text = freqText(t, lines[index], (v) => { lines[index] = v; update(); write(); },
      { placeholder: t('key.note.text.placeholder'), 'aria-label': t('note.line', { n: index + 1 }) });
    update();
    return h('div', { class: 'note-line' },
      h('div', { class: 'inline grow' }, text.el, counter,
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
  return h('div', { class: 'stack' }, known.el, lineEditor(t, sheet.values(section, key).map(parseLootList), {
    addLabel: t('stock.add_list'),
    blank: () => ({ list: '', weight: DEFAULT_CHANCE }),
    write,
    draw: (item, index, change) => h('div', { class: 'line-fields loot-line' },
      h('input', { type: 'text', value: lootLabel(item.list), list: known.el.id, spellcheck: 'false', title: item.list || null,
        placeholder: t(`key.note.${key}.placeholder`), 'aria-label': t('stock.list', { n: index + 1 }),
        onInput: (e) => { item.list = known.nameOf(e.target.value); e.target.title = item.list; change(); } }),
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

// The note's own item (item=): one item of the game, picked in the list.
function noteItem(ctx, section, key) {
  const { t, catalog, changed } = ctx;
  return itemChoice(t, catalog.itemIndex(), sheet.value(section, key) ?? '', (v) => { sheet.setValue(section, key, v); changed(); },
    { label: t(`key.note.${key}`) });
}

export const NOTE_EDITORS = {
  text: noteText,
  loot: lootLists,
  glovebox: lootLists,
  corpse,
  item: advanced(noteItem),
  key: ADVANCED,
};
