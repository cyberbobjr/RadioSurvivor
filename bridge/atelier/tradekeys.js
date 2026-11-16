// Forms of the [trade] keys (E22-T12, user 2026-11-15: nothing to type in a format; 2026-11-16: no item name typed):
// the trader's stock (item=, items picked in the item browser, each with its quantity "from ... to ..." or a lot, its
// weight shown), what the voice accepts as payment (accept=, E23-T06: whole categories ticked and items picked, only
// what has a trade value), the lots (group=name:total[:kinds]),
// the meeting places (landing=, check boxes of the voice's places used as trade meeting points), the meeting hours,
// the days between two visits, the quiet delay and the margin. Registered in stock.js KEY_EDITORS.

import { acceptChoices } from './categories.js';
import { h, select } from './dom.js';
import { field } from './fields.js';
import { hint } from './help.js';
import { addItemsButton, itemChoice } from './itempicker.js';
import * as sheet from './sheet.js';
import { formatGroup, formatList, formatMargin, formatStockItem, formatTimeRange, groupName, parseGroup, parseList,
  parseMargin, parseStockItem, parseTimeRange } from './values.js';
import * as voice from './voice.js';
import { button, checkboxes, lineEditor, numberInput, timeRange } from './widgets.js';

// What a trader's lists offer (E22-T17): only the items with a trade value, as the browser says.
const SELLABLE_NOTE = 'browser.sellable_only';
// Names of a category's items in its tooltip, at most this many.
const MAX_TIP_NAMES = 30;

// Use of a place ([place] use=) that makes it a trade meeting point (RS_Persona tradeLanding).
const LANDING_USE = 'landing';

const lotNames = (section) => sheet.values(section, 'group').map(groupName).filter(Boolean);

// Cells of the quantity of a stock line: the mode (a number, or one of the lots of the section; only when the section
// has lots) and "from ... to ...", an empty cell of the same width when a lot gives the quantity (theme.css grid).
function amountCells(t, item, lots, change, redraw) {
  const inLot = lots.includes(item.amount);
  const range = inLot ? h('span', { class: 'cell-empty' })
    : field('range', { t, value: item.amount, onChange: (v) => { item.amount = v; change(); } });
  if (!lots.length) return [range];
  const mode = select([{ value: '', label: t('stock.count') }, ...lots.map((g) => ({ value: g, label: t('stock.in_group', { name: g }) }))],
    inLot ? item.amount : '', (v) => { item.amount = v || '1'; change(); redraw(); }, { 'aria-label': t('stock.amount') });
  return [mode, range];
}

// Item lines of a list: the item as a read-only label (a click replaces it, itempicker.js), then `cells`; "Add items"
// opens the item browser in multiple choice, `toLine(type)` making the line of a ticked item. `offered(catalog)` is the
// index of the items the lines may hold, `note` the browser's line saying so (or null). Every item appears once.
function itemLines(ctx, { lines, write, offered, note = null, toLine, rowClass, label, cells = () => [] }) {
  const { t, catalog } = ctx;
  const items = catalog.itemIndex();
  const offer = offered(catalog);
  return lineEditor(t, lines, {
    write,
    tools: (addLines, list) => [
      addItemsButton(t, offer, { note, taken: () => list.map((l) => l.type), onAdd: (types) => addLines(types.map(toLine)) }),
      hint(t, 'help.ui.item_browser', { label: t('browser.add_items') })],
    draw: (line, index, change, list) => h('div', { class: `line-fields ${rowClass}` },
      itemChoice(t, items, line.type, (v) => { line.type = v; change(); }, { offer, note, label: label(index),
        taken: () => list.map((l) => l.type) }),
      ...cells(line, change)),
  });
}

// Lines "Module.Type:quantity" ([trade] item=, own [category] item=): each item with its quantity. Every line has the
// same cells: item | mode | range.
const stockLines = (offered, note = null) => (ctx, section, key) => {
  const { t, changed } = ctx;
  const lots = lotNames(section);
  const host = h('div', { class: 'stack' });
  const draw = () => {
    const lines = sheet.values(section, key).map(parseStockItem);
    host.replaceChildren(itemLines(ctx, {
      lines, offered, note, rowClass: `stock-line${lots.length ? ' with-lots' : ''}`,
      write: (list) => { sheet.setValues(section, key, list.map(formatStockItem)); changed(); },
      toLine: (type) => ({ type, amount: '1' }),
      label: (index) => t('stock.item', { n: index + 1 }),
      cells: (item, change) => amountCells(t, item, lots, change, draw),
    }));
  };
  draw();
  return host;
};

// An own [category]: any item of the game. The trader's stock: only the items a trader can sell (E22-T17).
export const stockItems = stockLines((catalog) => catalog.itemIndex());
const traderStock = stockLines((catalog) => catalog.sellableItemIndex(), SELLABLE_NOTE);

// accept= (E23-T06): a value naming an item (Module.Type) or a category, as RS_Persona.lua tells them apart.
const isItemValue = (value) => value.includes('.');

// One category check box: its name, how many of its items the voice accepts, their names in the tooltip; a category
// already in the sheet that the game would refuse (no item with a trade value, or unknown) stays, said as such, to be
// unticked.
function categoryOption(t, items, { id, sellable }) {
  const names = [...new Set(sellable.map((type) => items.get(type, t.lang)?.name ?? type))]
    .sort((a, b) => a.localeCompare(b, t.lang));
  const tip = names.length > MAX_TIP_NAMES ? `${names.slice(0, MAX_TIP_NAMES).join(', ')}…` : names.join(', ');
  return { value: id, label: t(`category.${id}`, {}, id),
    help: sellable.length ? t('accept.count', { n: sellable.length }) : t('accept.no_value'), title: tip || null };
}

// What the voice accepts as payment: whole categories (check boxes of those with at least one item with a trade value)
// and items picked in the sellable list. Written categories first, then items.
function accepted(ctx, section, key) {
  const { t, catalog, model, changed } = ctx;
  const values = sheet.values(section, key);
  let categories = values.filter((v) => !isItemValue(v));
  let types = values.filter(isItemValue);
  const write = () => { sheet.setValues(section, key, [...categories, ...types]); changed(); };
  const items = catalog.itemIndex();
  const choices = acceptChoices(model, catalog);
  const known = new Set(choices.map((c) => c.id));
  const options = [...choices.filter((c) => c.sellable.length || categories.includes(c.id)),
    ...categories.filter((id) => !known.has(id)).map((id) => ({ id, sellable: [] }))].map((c) => categoryOption(t, items, c));
  return h('div', { class: 'stack accept' },
    h('p', { class: 'help', text: t('accept.categories') }),
    checkboxes(options, categories, (list) => { categories = list; write(); }, { class: 'checks accept-categories' }),
    h('p', { class: 'help', text: t('accept.items') }),
    itemLines(ctx, {
      lines: types.map((type) => ({ type })), offered: (c) => c.sellableItemIndex(), note: SELLABLE_NOTE,
      rowClass: 'accept-line', toLine: (type) => ({ type }), label: (index) => t('accept.item', { n: index + 1 }),
      write: (list) => { types = list.map((l) => l.type); write(); },
    }));
}

// A lot name the game accepts (a-z first, then a-z 0-9 _), not taken by another lot of the section.
function lotId(text, taken) {
  const base = voice.slug(text, 'lot').replace(/^[^a-z]+/, '') || 'lot';
  let id = base;
  for (let n = 2; taken.includes(id); n += 1) id = `${base}_${n}`;
  return id;
}

// Lots of the stock (group=name:total[:kinds]): name, "from ... to ..." in all, "at most N kinds". A renamed lot keeps
// its stock lines; a lot added, removed or renamed redraws the panel (the stock lines offer the lots by name).
function lots(ctx, section, key) {
  const { t, changed, rerender } = ctx;
  const write = (list) => {
    const before = lotNames(section).join(',');
    sheet.setValues(section, key, list.map(formatGroup));
    changed();
    if (lotNames(section).join(',') !== before) rerender();
  };
  const rename = (lot, text) => {
    const old = lot.name;
    lot.name = text.trim() ? lotId(text, lotNames(section).filter((n) => n !== old)) : '';
    const stock = sheet.values(section, 'item').map(parseStockItem)
      .map((item) => (old && item.amount === old ? { ...item, amount: lot.name || '1' } : item));
    sheet.setValues(section, 'item', stock.map(formatStockItem));
  };
  return lineEditor(t, sheet.values(section, key).map(parseGroup), {
    addLabel: t('lot.add'),
    blank: () => ({ name: '', total: '1-3', kinds: '' }),
    write,
    draw: (lot, index, change) => h('div', { class: 'line-fields lot' },
      h('input', { type: 'text', class: 'lot-name', value: lot.name, spellcheck: 'false', placeholder: t('lot.name_placeholder'),
        'aria-label': t('lot.name', { n: index + 1 }),
        onChange: (e) => { rename(lot, e.target.value); change(); } }),
      h('span', { class: 'inline lot-total' }, field('range', { t, value: lot.total, onChange: (v) => { lot.total = v; change(); } }),
        t('lot.in_all')),
      h('span', { class: 'inline lot-kinds' }, t('lot.kinds_before'),
        numberInput(lot.kinds, (v) => { lot.kinds = v; change(); }, { min: 1, 'aria-label': t('lot.kinds') }),
        t('lot.kinds_after'))),
  });
}

// Meeting places: check boxes of the voice's places used as trade meeting points, or the way to the Places panel.
function landing(ctx, section, key) {
  const { t, model, changed } = ctx;
  const spots = voice.places(model).filter((p) => p.uses.includes(LANDING_USE));
  if (!spots.length) {
    return h('div', { class: 'stack' }, h('p', { class: 'warnline', text: t('trade.no_landing') }),
      h('div', {}, button('neutral', { class: 'to-places', onClick: () => ctx.show('place') }, t('trade.to_places'))));
  }
  return checkboxes(spots.map((p) => ({ value: p.id, label: p.label || p.id })), parseList(sheet.value(section, key)),
    (list) => { sheet.setValue(section, key, formatList(list)); changed(); }, { class: 'checks landing' });
}

function meetingHours(ctx, section, key) {
  const { t, changed } = ctx;
  return timeRange(t, parseTimeRange(sheet.value(section, key)), (range) => {
    sheet.setValue(section, key, formatTimeRange(range));
    changed();
  }, { fromLabel: t('trade.hours_start'), toLabel: t('trade.hours_end') });
}

// "<before> [number] <after>": one number of the section, `attrs` its bounds.
const numberKey = (before, after, attrs) => (ctx, section, key) => {
  const { t, changed } = ctx;
  return h('span', { class: 'inline' }, before && t(before),
    numberInput(sheet.value(section, key) ?? '', (v) => { sheet.setValue(section, key, v); changed(); },
      { 'aria-label': t(`key.trade.${key}`), ...attrs }),
    t(after));
};

// Margin "0.10-0.50" shown as "from 10 % to 50 %"; both empty: no line (the game's default margin).
function margin(ctx, section, key) {
  const { t, changed } = ctx;
  const current = parseMargin(sheet.value(section, key));
  const write = () => { sheet.setValue(section, key, formatMargin(current)); changed(); };
  const pct = (side, label, placeholder) => numberInput(current[side], (v) => { current[side] = v; write(); },
    { min: 0, max: 100, step: 5, placeholder, 'aria-label': label });
  return h('span', { class: 'inline' }, t('field.from'), pct('min', t('field.min'), '10'), h('span', { text: '%' }),
    t('field.to'), pct('max', t('field.max'), '50'), h('span', { text: '%' }));
}

export const TRADE_EDITORS = {
  item: traderStock,
  group: lots,
  accept: accepted,
  landing,
  hours: meetingHours,
  every_days: numberKey('trade.every', 'trade.days', { min: 1, max: 28 }),
  delay_hours: numberKey(null, 'trade.hours_unit', { min: 0, max: 48, step: 0.5, inputmode: 'decimal' }),
  margin,
};
