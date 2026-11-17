// "Dashboard" view (E24-T05, option A of the mockup chosen by the user 2026-11-17): every voice of the working folder on
// one screen: summary tiles, filters as chips, then a table, one row per voice: its state, the radio it needs, its
// listening hours over 24 h and what the player can do with it. A click on a row opens the voice in the editor.
// The voices are read with the page's own readers (sheet.js, voice.js, the catalogue's radio levels): no rule of the
// game is written here beyond what those readers say. Pure functions are exported for the node benches.

import { h } from './dom.js';
import * as sheet from './sheet.js';
import { isTime, parseHours, parseList } from './values.js';
import * as voice from './voice.js';
import { refusedByGame } from './voicelist.js';
import { button } from './widgets.js';

const DAY = 24;
const BAR_MARKS = [6, 12, 18];                // thin marks on the 24 h bar

// --- reading a voice ------------------------------------------------------------------------------------------------
const hourOf = (text) => Number(text.slice(0, 2)) + Number(text.slice(3, 5)) / 60;

// listen= as ranges of hours of the day ([from, to), fractional), a range over midnight split in two; always or no
// listen= line: the whole day. Unreadable parts are left out (the game refuses the voice anyway).
export function listenRanges(listen) {
  const parts = parseHours(listen);
  if (!parts.length) return [[0, DAY]];
  return parts.filter(([from, to]) => isTime(from) && isTime(to)).flatMap(([from, to]) => {
    const a = hourOf(from);
    const b = hourOf(to);
    return b > a ? [[a, b]] : [[a, DAY], ...(b > 0 ? [[0, b]] : [])];
  });
}

export const isAlways = (listen) => parseHours(listen).length === 0;

export const listenHours = (listen) => listenRanges(listen).reduce((sum, [a, b]) => sum + b - a, 0);

const listensAt = (ranges, hour) => ranges.some(([a, b]) => hour >= a && hour < b);

// "7 h–10 h · 16 h–19 h" in the page language; "day and night" for always. Ranges as written (not split).
export function hoursText(t, listen) {
  if (isAlways(listen)) return t('dashboard.hours.always');
  const time = (text) => {
    const hour = Number(text.slice(0, 2));
    const minutes = text.slice(3, 5);
    return minutes === '00' ? t('dashboard.hour', { h: hour }) : t('dashboard.hour_min', { h: hour, m: minutes });
  };
  return parseHours(listen).filter(([from, to]) => isTime(from) && isTime(to))
    .map(([from, to]) => `${time(from)}–${time(to)}`).join(' · ');
}

// What the dashboard knows of a voice: entry of GET /api/voices + its sheet model, read with sheet.js and voice.js.
export function summarize(entry, model, catalog) {
  const head = model.head;
  const actions = parseList(sheet.value(head, 'actions'));
  const trade = sheet.section(model, 'trade');
  const frequency = sheet.value(head, 'frequency');
  const state = sheet.value(head, 'state') ?? 'active';
  const listen = sheet.value(head, 'listen');
  return {
    id: entry.id,
    name: sheet.value(head, 'name') || entry.name || entry.id,
    state,
    active: state === 'active',
    level: frequency !== null ? catalog.frequencyLevel(frequency) : sheet.value(head, 'radio'),
    listen,
    always: isAlways(listen),
    ranges: listenRanges(listen),
    hours: listenHours(listen),
    missions: voice.missions(model).length,
    trader: actions.includes('propose_trade') || trade !== null,
    arrival: trade ? sheet.value(trade, 'arrival') : null,
    share: actions.includes('share_frequency'),
    calls: Number(sheet.value(head, 'call_one_in') ?? 0) > 0,
    rescue: sheet.value(head, 'location') === 'rescue',
  };
}

// What the player can do with a voice: the chips of the filter and the tags of a row, in this order. A new kind is
// one more entry here and its strings (dashboard.kind.<id>, .icon); `tag` words the tag of a row when the name of the
// kind is not enough (the count of missions, the way a trader comes).
export const KINDS = [
  { id: 'talk', has: () => true },
  { id: 'missions', has: (v) => v.missions > 0,
    tag: (t, v) => t(v.missions === 1 ? 'dashboard.tag.mission_one' : 'dashboard.tag.missions', { n: v.missions }) },
  { id: 'trade', has: (v) => v.trader,
    tag: (t, v) => (v.arrival ? t(`dashboard.tag.trade.${v.arrival}`, {}, t('dashboard.kind.trade')) : t('dashboard.kind.trade')) },
  { id: 'share', has: (v) => v.share },
  { id: 'calls', has: (v) => v.calls },
  { id: 'rescue', has: (v) => v.rescue },
];

export const interactions = (v) => KINDS.filter((k) => k.has(v));

export const tagText = (t, kind, v) => (kind.tag ? kind.tag(t, v) : t(`dashboard.kind.${kind.id}`));

// 1 for the weakest radio of the catalogue... 0 when the voice names none the radios tune.
export const levelRank = (catalog, level) => catalog.radioLevels().findIndex((l) => l.id === level) + 1;

// Hours of the day (whole hours, read at half past) when no voice listens except the "day and night" ones; a silent
// voice fills no gap.
export function gapHours(rows) {
  const filling = rows.filter((v) => v.active && !v.always);
  return Array.from({ length: DAY }, (_, hour) => hour)
    .filter((hour) => !filling.some((v) => listensAt(v.ranges, hour + 0.5))).length;
}

// Counts of the summary tiles, over every voice shown (not the filtered ones).
export function tiles(rows, catalog) {
  const simple = catalog.radioLevels()[0]?.id;
  return {
    voices: rows.length,
    traders: rows.filter((v) => v.trader).length,
    missions: rows.filter((v) => v.missions > 0).length,
    simple: rows.filter((v) => v.level === simple).length,
    gap: gapHours(rows),
    silent: rows.filter((v) => !v.active).length,
  };
}

export function filterRows(rows, { kind, level }) {
  const wanted = KINDS.find((k) => k.id === kind);
  return rows.filter((v) => (!wanted || wanted.has(v)) && (!level || v.level === level));
}

// Sort keys of the columns; ties are broken by name.
const SORTS = {
  name: () => 0,
  radio: (v, catalog) => levelRank(catalog, v.level) * 100 + (v.ranges[0]?.[0] ?? 0),
  hours: (v) => -v.hours,
  kinds: (v) => -interactions(v).length,
};
export const SORT_KEYS = Object.keys(SORTS);

export function sortRows(rows, key, direction = 1, catalog = null) {
  const of = SORTS[key] ?? SORTS.name;
  return [...rows].sort((a, b) => {
    const x = of(a, catalog);
    const y = of(b, catalog);
    const byKey = x < y ? -1 : x > y ? 1 : 0;
    return direction * (byKey || a.name.localeCompare(b.name));
  });
}

// --- the view -------------------------------------------------------------------------------------------------------
// api: {voices(), read(id)}; t: strings; catalog; open(id): opens a voice in the editor; verdicts(): the game's
// verdicts (GET /api/verdicts) for the refused mark.
export function createDashboard({ api, t, catalog, open, verdicts = () => ({}) }) {
  const state = { rows: null, filter: { kind: null, level: null }, sort: 'radio', direction: 1, loading: 0 };
  const tileHost = h('div', { class: 'dash-tiles' });
  const filterHost = h('div', { class: 'dash-filters' });
  const tableHost = h('div', { class: 'dash-tablebox' });

  const levelName = (id) => t(`dashboard.radio.${id}`, {}, t(`radio.${id}.name`));

  function radioCell(v) {
    const rank = levelRank(catalog, v.level);
    if (!rank) return h('span', { class: 'dash-radio muted', text: t('dashboard.radio_none') });
    return h('span', { class: 'dash-radio', title: t(`help.head.radio.${v.level}.what`), 'data-level': v.level },
      h('span', { class: 'dash-dots', 'aria-hidden': 'true' },
        catalog.radioLevels().map((l, index) => h('i', { class: index < rank ? 'on' : null }))),
      levelName(v.level));
  }

  function hoursCell(v) {
    const text = hoursText(t, v.listen);
    const bar = h('div', { class: 'dash-hours', role: 'img', 'aria-label': text },
      BAR_MARKS.map((hour) => h('em', { style: `left:${(hour / DAY) * 100}%` })),
      v.ranges.map(([a, b]) => h('span', { style: `left:${(a / DAY) * 100}%;width:${((b - a) / DAY) * 100}%` })));
    return [bar, h('div', { class: 'dash-htext', text })];
  }

  const tagsCell = (v) => h('span', { class: 'dash-tags' }, interactions(v).map((k) => h('span', { class: 'dash-tag', 'data-kind': k.id },
    h('span', { 'aria-hidden': 'true', text: t(`dashboard.kind.${k.id}.icon`) }), tagText(t, k, v))));

  function row(v) {
    const refused = refusedByGame(verdicts(), v.id);
    return h('tr', { class: 'dash-row', 'data-voice': v.id, onClick: () => open(v.id) },
      h('td', { class: 'dash-name' },
        h('button', { type: 'button', class: 'dash-open', title: t('dashboard.open') },
          h('b', { text: v.name }),
          refused && h('span', { class: 'gamebad', title: t('verdict.dot') }),
          refused && h('span', { class: 'sr', text: ` (${t('verdict.dot')})` })),
        h('small', { class: `dash-state ${v.active ? '' : 'silent'}`.trim(),
          text: t(`dashboard.state.${v.state}`, {}, t('dashboard.state.silent')) })),
      h('td', {}, radioCell(v)),
      h('td', {}, hoursCell(v)),
      h('td', {}, tagsCell(v)));
  }

  function header(key) {
    const on = state.sort === key;
    return h('th', { 'aria-sort': on ? (state.direction > 0 ? 'ascending' : 'descending') : null },
      h('button', { type: 'button', class: `dash-sort${on ? ' on' : ''}`, 'data-sort': key, title: t('dashboard.sort'),
        onClick: () => {
          state.direction = on ? -state.direction : 1;
          state.sort = key;
          renderTable();
        } }, t(`dashboard.col.${key}`)));
  }

  function renderTable() {
    if (state.rows === null) { tableHost.replaceChildren(h('p', { class: 'muted', text: t('dashboard.loading') })); return; }
    const list = sortRows(filterRows(state.rows, state.filter), state.sort, state.direction, catalog);
    if (!list.length) {
      const filtered = state.filter.kind || state.filter.level;
      tableHost.replaceChildren(h('div', { class: 'dash-empty' }, h('p', { class: 'empty',
        text: t(filtered ? 'dashboard.empty' : 'dashboard.none') }),
      filtered && button('neutral', { id: 'dash-clear', onClick: () => { state.filter = { kind: null, level: null }; render(); } },
        t('dashboard.clear'))));
      return;
    }
    tableHost.replaceChildren(h('table', { class: 'dash-table' },
      h('thead', {}, h('tr', {}, SORT_KEYS.map(header))),
      h('tbody', {}, list.map(row))));
  }

  function renderTiles() {
    const counts = state.rows ? tiles(state.rows, catalog) : null;
    tileHost.replaceChildren(...Object.keys(tiles([], catalog)).map((key) => h('div', { class: 'dash-tile', 'data-tile': key },
      h('div', { class: 'n', text: counts ? t(`dashboard.tile.${key}.n`, { n: counts[key] }, String(counts[key])) : '…' }),
      h('div', { class: 'l', text: t(`dashboard.tile.${key}`) }))));
  }

  function renderFilters() {
    const chips = (key, options) => options.map((o) => h('button', { type: 'button', class: 'dash-chip', 'data-filter': key,
      'data-value': o.id, 'aria-pressed': String(state.filter[key] === o.id), onClick: () => {
        state.filter[key] = state.filter[key] === o.id ? null : o.id;
        render();
      } }, o.text));
    filterHost.replaceChildren(
      h('div', { class: 'dash-chips' },
        h('span', { class: 'lab', text: t('dashboard.filter.kinds') }),
        chips('kind', KINDS.map((k) => ({ id: k.id, text: `${t(`dashboard.kind.${k.id}.icon`)} ${t(`dashboard.kind.${k.id}`)}` })))),
      h('div', { class: 'dash-chips' },
        h('span', { class: 'lab', text: t('dashboard.filter.radio') }),
        chips('level', catalog.radioLevels().map((l) => ({ id: l.id, text: `${t(`radio.${l.id}.icon`)} ${levelName(l.id)}` })))));
  }

  function render() {
    renderTiles();
    renderFilters();
    renderTable();
  }

  // Reads every voice of the list (the removed ones left out) again: the dashboard shows what is saved.
  async function refresh() {
    const ticket = ++state.loading;
    const listed = await api.voices();
    if (!listed.ok) return;
    const entries = (listed.voices ?? []).filter((entry) => !entry.removed);
    const read = await Promise.all(entries.map(async (entry) => [entry, await api.read(entry.id)]));
    if (ticket !== state.loading) return;                 // a newer refresh started meanwhile
    state.rows = read.filter(([, result]) => result.ok && (result.text ?? '').trim())
      .map(([entry, result]) => summarize(entry, sheet.parse(result.text), catalog));
    render();
  }

  const el = h('section', { class: 'dashboard', id: 'dashboard', 'aria-label': t('tab.dashboard') },
    h('div', { class: 'toolbar' }, h('div', { class: 'title' }, h('h2', { text: t('dashboard.title') }))),
    h('p', { class: 'help', text: t('dashboard.help') }),
    h('div', { class: 'dash-panel' }, tileHost, filterHost),
    tableHost);
  render();
  // redraw: the game's verdicts changed (the refused mark), nothing read again
  return { el, refresh, start: refresh, redraw: () => { if (state.rows) renderTable(); } };
}
