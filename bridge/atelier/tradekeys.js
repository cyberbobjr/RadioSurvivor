// Forms of the [trade] keys (E22-T12, user 2026-11-15: nothing to type in a format): the trader's stock (item=, an
// item searched by name, its quantity "from ... to ..." or a lot, its weight shown), the lots (group=name:total[:kinds]),
// the meeting places (landing=, check boxes of the voice's places used as trade meeting points), the meeting hours,
// the days between two visits, the quiet delay and the margin. Registered in stock.js KEY_EDITORS.

import { h, select } from './dom.js';
import { field } from './fields.js';
import { hint } from './help.js';
import { browseButton } from './itembrowser.js';
import { itemPicker } from './itempicker.js';
import * as sheet from './sheet.js';
import { formatGroup, formatList, formatMargin, formatStockItem, formatTimeRange, groupName, parseGroup, parseList,
  parseMargin, parseStockItem, parseTimeRange } from './values.js';
import * as voice from './voice.js';
import { button, checkboxes, lineEditor, numberInput, timeRange } from './widgets.js';

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

// Lines "Module.Type:quantity" ([trade] item=, own [category] item=): the item searched by name or picked in the item
// browser (several at once), its weight shown, its quantity. Every line has the same cells: item | mode | range.
export function stockItems(ctx, section, key) {
  const { t, catalog, changed } = ctx;
  const lots = lotNames(section);
  const items = catalog.itemIndex();
  const write = (list) => { sheet.setValues(section, key, list.map(formatStockItem)); changed(); };
  const host = h('div', { class: 'stack' });
  const draw = () => host.replaceChildren(lineEditor(t, sheet.values(section, key).map(parseStockItem), {
    addLabel: t('stock.add'),
    blank: () => ({ type: '', amount: '1' }),
    write,
    tools: (addLines) => [browseButton(t, items, { multi: true, onPick: (type) => addLines([{ type, amount: '1' }]) }),
      hint(t, 'help.ui.item_browser', { label: t('browser.open') })],
    draw: (item, index, change) => h('div', { class: `line-fields stock-line${lots.length ? ' with-lots' : ''}` },
      itemPicker(t, items, item.type, (v) => { item.type = v; change(); }, { 'aria-label': t('stock.item', { n: index + 1 }) }),
      ...amountCells(t, item, lots, change, draw)),
  }));
  draw();
  return host;
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
  item: stockItems,
  group: lots,
  landing,
  hours: meetingHours,
  every_days: numberKey('trade.every', 'trade.days', { min: 1, max: 28 }),
  delay_hours: numberKey(null, 'trade.hours_unit', { min: 0, max: 48, step: 0.5, inputmode: 'decimal' }),
  margin,
};
