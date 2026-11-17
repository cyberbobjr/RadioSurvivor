// Forms of the [note] keys (E22-T07, E22-T12, user 2026-11-15): the text written on the note (text=, one line each,
// live count of the game's limit, %1 = the voice's frequency) and the optional themed places on top of the common base
// the game applies to every note (E24-T03, RS_NotesBase.lua: papers, glove boxes, zombies): loot= and glovebox=,
// lists of the game picked in the browser (no name typed: lootindex.js) and Rarely / Normally / Often. The note's own
// item and text key (item=, key=, shipped voices only) stay in the advanced settings of the form (sectionform.js
// advanced), the item picked in the item browser like every item of the page. Registered in stock.js KEY_EDITORS.

import { forAi, inputPropose } from './ai.js';
import { h } from './dom.js';
import { hint } from './help.js';
import { openItemBrowser } from './itembrowser.js';
import { itemChoice } from './itempicker.js';
import { createLootIndex, lootLabel } from './lootindex.js';
import { ADVANCED, advanced } from './sectionform.js';
import * as sheet from './sheet.js';
import { DEFAULT_CHANCE, FREQUENCY_MARK, formatLootList, parseLootList, utf8Bytes } from './values.js';
import { button, chanceChoice, freqText, lineEditor, removeButton } from './widgets.js';

// Limits of a note text line, as RS_Persona.lua reads them (MAX_NOTE_LINES, MAX_NOTE_LINE_BYTES, writtenText): the
// catalogue grammar does not carry them.
const MAX_LINES = 8;
const MAX_BYTES = 40;
const FREQUENCY = FREQUENCY_MARK;
const OWN_ITEM_KEYS = ['item', 'key'];
const badText = (text) => /[<>^]/.test(text) || text.split(FREQUENCY).join('').includes('%');

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
    // E24-T04: the AI proposes the line from the voice and the other lines of the note (the frequency as it writes it).
    text.el.append(inputPropose(ctx, 'note_line', text.input, { freqWord: t('freq.word'), details: () => ({
      other_lines: lines.filter((line, other) => other !== index && line.trim()).map(forAi).join(' / '),
      line_number: String(index + 1) }) }));
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

// Themed places (loot=, glovebox=): lists of the game added from the browser (search, kind, ticks), each line its
// name in words (the game's name in the tooltip), read-only, with how often and x.
function lootLists(ctx, section, key) {
  const { t, catalog, changed } = ctx;
  const lists = createLootIndex(catalog.lootLists(key), (kind) => t(`lootkind.${kind}`, {}, kind));
  const write = (items) => { sheet.setValues(section, key, items.map(formatLootList)); changed(); };
  const addLabel = t(`note.add_${key}`);
  return lineEditor(t, sheet.values(section, key).map(parseLootList), {
    write,
    tools: (addLines, list) => [
      button('add', { class: 'add-places', onClick: () => openItemBrowser(t, lists, { multi: true, words: 'lootbrowser',
        taken: list.map((l) => l.list), onAdd: (names) => addLines(names.map((n) => ({ list: n, weight: DEFAULT_CHANCE }))) }) },
      addLabel),
      hint(t, 'help.ui.lootbrowser_browser', { label: addLabel })],
    draw: (item, index, change) => h('div', { class: 'line-fields loot-line' },
      h('span', { class: 'loot-name', title: item.list, text: lootLabel(item.list),
        'aria-label': t('stock.list', { n: index + 1 }) + ' : ' + lootLabel(item.list) }),
      chanceChoice(t, item.weight, (v) => { item.weight = v; change(); }, { 'aria-label': t('stock.chance') })),
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
  item: advanced(noteItem),
  key: ADVANCED,
};
