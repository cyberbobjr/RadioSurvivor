// Forms of the [trade] keys (E22-T12, user 2026-11-15: nothing to type in a format; 2026-11-16: no item name typed;
// E24-T02: no number, id or weight on screen): what the trader sells (item=, items picked in the item list, each with
// "between n and m"), the paquets (group=, paquets.js: a name typed, its id made from it, its items picked in the list,
// its total and its number of different items as steppers), what the voice accepts as payment (accept=, E23-T06:
// whole categories ticked and items picked, only what a trader can buy), the meeting places (landing=), the meeting
// hours, the days between two visits, the quiet delay and the margin as named steps (scales.js).
// Registered in stock.js KEY_EDITORS.

import { inputPropose } from './ai.js';
import { acceptChoices } from './categories.js';
import { h } from './dom.js';
import { hint } from './help.js';
import { addItemsButton, itemChoice } from './itempicker.js';
import * as paquets from './paquets.js';
import * as sheet from './sheet.js';
import { stepChoice } from './stepchoice.js';
import { formatList, formatStockItem, formatTimeRange, parseList, parseStockItem, parseTimeRange } from './values.js';
import * as voice from './voice.js';
import { button, checkboxes, lineEditor, rangeStepper, removeButton, stepper, textInput, timeRange } from './widgets.js';

// What a trader's lists offer (E22-T17): only the items with a trade value, as the browser says.
const SELLABLE_NOTE = 'browser.sellable_only';
// Names of a category's items in its tooltip, at most this many.
const MAX_TIP_NAMES = 30;

// Use of a place ([place] use=) that makes it a trade meeting point (RS_Persona tradeLanding).
const LANDING_USE = 'landing';

// Item lines of a list: the item as a read-only label (a click replaces it, itempicker.js), then `cells`; the add button
// (`addLabel`) opens the item browser in multiple choice, `toLine(type)` making the line of a ticked item. `offered(catalog)`
// is the index of the items the lines may hold, `note` the browser's line saying so (or null), `taken()` every item
// already in the section (an item appears once).
function itemLines(ctx, { lines, write, offered, note = null, toLine, rowClass, label, addLabel, taken, cells = () => [] }) {
  const { t, catalog } = ctx;
  const items = catalog.itemIndex();
  const offer = offered(catalog);
  return lineEditor(t, lines, {
    write,
    tools: (addLines, list) => [
      addItemsButton(t, offer, { note, label: addLabel, taken: () => [...new Set([...taken(), ...list.map((l) => l.type)])],
        onAdd: (types) => addLines(types.map(toLine)) }),
      hint(t, 'help.ui.item_browser', { label: addLabel })],
    draw: (line, index, change, list) => h('div', { class: `line-fields ${rowClass}` },
      itemChoice(t, items, line.type, (v) => { line.type = v; change(); }, { offer, note, label: label(index),
        taken: () => [...taken(), ...list.map((l) => l.type)] }),
      ...cells(line, change)),
  });
}

// "Item: between n and m" lines (an own [category] item=): every item of the game.
export function stockItems(ctx, section, key) {
  const { t, changed } = ctx;
  return itemLines(ctx, {
    lines: sheet.values(section, key).map(parseStockItem),
    offered: (catalog) => catalog.itemIndex(), rowClass: 'stock-line', addLabel: t('browser.add_items'),
    taken: () => [], label: (index) => t('stock.item', { n: index + 1 }),
    write: (list) => { sheet.setValues(section, key, list.map(formatStockItem)); changed(); },
    toLine: (type) => ({ type, amount: '1' }),
    cells: (item, change) => [rangeStepper(t, item.amount, (v) => { item.amount = v; change(); }, { min: 1 })],
  });
}

// What the trader sells outside the paquets: only the items a trader can sell (E22-T17).
function traderStock(ctx, section) {
  const { t, changed } = ctx;
  return itemLines(ctx, {
    lines: paquets.looseItems(section), offered: (catalog) => catalog.sellableItemIndex(), note: SELLABLE_NOTE,
    rowClass: 'stock-line', addLabel: t('trade.add_sold'), taken: () => paquets.stockTypes(section),
    label: (index) => t('stock.item', { n: index + 1 }),
    write: (list) => { paquets.setLooseItems(section, list.filter((l) => l.type)); changed(); },
    toLine: (type) => ({ type, amount: '1' }),
    cells: (item, change) => [rangeStepper(t, item.amount, (v) => { item.amount = v; change(); }, { min: 1 })],
  });
}

// accept= (E23-T06): a value naming an item (Module.Type) or a category, as RS_Persona.lua tells them apart.
const isItemValue = (value) => value.includes('.');

// One category check box: its name and how many of its items the voice takes, their names in the tooltip; a category
// already in the sheet that the game would refuse (nothing a trader buys, or unknown) stays, said as such, to be
// unticked.
function categoryOption(t, items, { id, sellable }) {
  const names = [...new Set(sellable.map((type) => items.get(type, t.lang)?.name ?? type))]
    .sort((a, b) => a.localeCompare(b, t.lang));
  const tip = names.length > MAX_TIP_NAMES ? `${names.slice(0, MAX_TIP_NAMES).join(', ')}…` : names.join(', ');
  return { value: id, label: t(`category.${id}`, {}, voice.labelOf(id)),
    help: sellable.length ? t('accept.count', { n: sellable.length }) : t('accept.no_value'), title: tip || null };
}

// What the voice accepts as payment: whole categories and items picked in the sellable list.
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
      addLabel: t('trade.add_taken'), taken: () => [],
      write: (list) => { types = list.map((l) => l.type); write(); },
    }));
}

// Names of items in the page language, as the AI is told them (the details of a paquet name, E24-T04).
const itemNames = (ctx, types) => types.map((type) => ctx.catalog.itemIndex().get(type, ctx.t.lang)?.name ?? type).join(', ');

// One paquet: its name (typed, shown back from its id), "between n and m in all", "no more than N different items",
// its items picked in the list.
function paquetCard(ctx, section, paquet) {
  const { t, catalog, changed, rerender } = ctx;
  const items = catalog.itemIndex();
  const offer = catalog.sellableItemIndex();
  const name = textInput(null, paquet.label, () => {}, { class: 'paquet-name', 'aria-label': t('lot.name'),
    onChange: (e) => { paquets.rename(section, paquet.id, e.target.value.trim() || t('lot.default_name')); changed(); rerender(); } });
  return h('article', { class: 'card paquet', title: paquet.id, 'data-paquet': paquet.id },
    h('header', { class: 'card-head' }, h('span', { class: 'card-icon', 'aria-hidden': 'true', text: '📦' }), name,
      inputPropose(ctx, 'paquet_name', name, { event: 'change', details: () => ({ items: itemNames(ctx, paquet.items) }) }),
      removeButton(t, () => { paquets.remove(section, paquet.id); changed(); rerender(); }, t('lot.remove'))),
    h('div', { class: 'inline lot-total' },
      rangeStepper(t, paquet.total, (v) => { paquets.setTotal(section, paquet.id, v); changed(); }, { min: 1 }),
      t('lot.in_all')),
    h('div', { class: 'inline lot-kinds' }, t('lot.kinds_before'),
      stepper(paquet.kinds, (v) => { paquets.setKinds(section, paquet.id, v); changed(); },
        { min: 1, label: t('lot.kinds'), emptyLabel: t('lot.no_limit') }),
      t('lot.kinds_after')),
    paquet.items.length === 0 && h('p', { class: 'warnline', text: t('lot.empty') }),
    h('ul', { class: 'paquet-items' }, paquet.items.map((type) => h('li', { title: type },
      h('span', { text: items.get(type, t.lang)?.name ?? t('item.unknown') }),
      removeButton(t, () => { paquets.removeItem(section, type); changed(); rerender(); })))),
    addItemsButton(t, offer, { note: SELLABLE_NOTE, label: t('lot.add_items'), taken: () => paquets.stockTypes(section),
      onAdd: (types) => { paquets.addItems(section, paquet.id, types); changed(); rerender(); } }));
}

// The paquets of the stock: a card each, and "+ Add a paquet" with the name typed.
function lots(ctx, section) {
  const { t, changed, rerender } = ctx;
  let typed = '';
  const input = textInput(null, '', (v) => { typed = v; }, { placeholder: t('lot.name_placeholder'), 'aria-label': t('lot.name') });
  return h('div', { class: 'stack paquets' },
    paquets.list(section).map((p) => paquetCard(ctx, section, p)),
    h('div', { class: 'inline' }, input,
      inputPropose(ctx, 'paquet_name', input, { details: () => ({ items: itemNames(ctx, paquets.stockTypes(section)) }) }),
      button('add', { class: 'paquet-add', onClick: () => {
        paquets.addPaquet(section, typed.trim() || t('lot.default_name'));
        changed();
        rerender();
      } }, t('lot.add'))));
}

// Meeting places: check boxes of the voice's places used as trade meeting points, or a button that makes one (its name
// and use set, its square to give in the places step).
function landing(ctx, section, key) {
  const { t, model, changed } = ctx;
  const spots = voice.places(model).filter((p) => p.uses.includes(LANDING_USE));
  if (!spots.length) {
    return h('div', { class: 'stack' }, h('p', { class: 'warnline', text: t('trade.no_landing') }),
      h('div', {}, button('neutral', { class: 'to-places', onClick: () => {
        const place = voice.addPlace(model, { label: t('use.landing'), at: { x: '', y: '', z: '0' }, uses: [LANDING_USE] });
        sheet.setValue(section, key, place.id);
        ctx.ui.new_place = place.id;
        changed();
        ctx.show('place');
      } }, t('trade.make_landing'))));
  }
  return checkboxes(spots.map((p) => ({ value: p.id, label: p.label || voice.labelOf(p.id) })), parseList(sheet.value(section, key)),
    (list) => { sheet.setValue(section, key, formatList(list)); changed(); }, { class: 'checks landing' });
}

function meetingHours(ctx, section, key) {
  const { t, changed } = ctx;
  return timeRange(t, parseTimeRange(sheet.value(section, key)), (range) => {
    sheet.setValue(section, key, formatTimeRange(range));
    changed();
  }, { fromLabel: t('trade.hours_start'), toLabel: t('trade.hours_end') });
}

// A key of the section as named steps (scales.js trade.<key>).
const steps = (ctx, section, key) => stepChoice(ctx.t, 'trade', key, sheet.value(section, key), (v) => {
  sheet.setValue(section, key, v);
  ctx.changed();
});

export const TRADE_EDITORS = {
  item: traderStock,
  group: lots,
  accept: accepted,
  landing,
  hours: meetingHours,
  every_days: steps,
  delay_hours: steps,
  margin: steps,
};
