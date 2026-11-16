// Step 2, where and when: frequency band (overlap with the other voices shown), radio needed, listening hours,
// location on the map.

import { h } from '../dom.js';
import { choiceTopics, hint, withHint } from '../help.js';
import { mapLink } from '../maplink.js';
import * as sheet from '../sheet.js';
import { formatHours, freeBand, khzToMhz, overlaps, parseBands, parseHours } from '../values.js';
import { button, choice, fold, radios, removeButton, row, textInput, timeRange } from '../widgets.js';

function bandEditor({ model, catalog, t, voiceId, changed, rerender }) {
  const head = model.head;
  const fixed = sheet.value(head, 'frequencies');
  if (fixed && !sheet.value(head, 'frequency_range')) {
    return row(t('where.fixed'), (id) => textInput(id, fixed, (v) => { sheet.setValue(head, 'frequencies', v); changed(); }),
      t('where.fixed_help'), hint(t, 'help.head.frequencies', { label: t('where.fixed') }));
  }
  const taken = catalog.takenBands(voiceId);
  const bands = (parseBands(sheet.value(head, 'frequency_range')) ?? []).map(([lo, hi]) => [khzToMhz(lo), khzToMhz(hi)]);
  const warn = h('div', { class: 'warnline', 'aria-live': 'polite' });
  const refreshWarning = () => {
    const parsed = parseBands(formatRows()) ?? [];
    const hit = taken.filter((o) => parsed.some((b) => o.bands.some((x) => overlaps(b, x))));
    warn.textContent = hit.length ? t('where.overlap', { names: hit.map((o) => o.name).join(', ') }) : '';
  };
  const mhzText = (v) => (Number.isFinite(Number(v)) ? Number(v).toFixed(1) : String(v));
  const formatRows = () => bands.filter(([lo, hi]) => lo && hi).map(([lo, hi]) => `${mhzText(lo)}-${mhzText(hi)}`).join(',');
  const write = (structural) => {
    sheet.setValue(head, 'frequency_range', formatRows());
    changed();
    if (structural) rerender(); else refreshWarning();
  };
  const mhz = (value, onInput, label) => h('input', { type: 'number', min: 1, max: 999.8, step: 0.2, class: 'num',
    value, 'aria-label': label, onInput: (e) => onInput(e.target.value) });
  const suggest = () => {
    const mine = parseBands(formatRows()) ?? [];
    const band = freeBand([...taken.flatMap((o) => o.bands), ...mine]);
    if (band) { bands.push([khzToMhz(band[0]), khzToMhz(band[1])]); write(true); }
  };
  refreshWarning();
  return h('div', { class: 'form' },
    row(t('where.band'), (id) => h('div', { class: 'stack', id },
      bands.map((band, index) => h('div', { class: 'inline' },
        t('field.from'), mhz(band[0], (v) => { band[0] = v; write(false); }, t('where.band_low')),
        t('field.to'), mhz(band[1], (v) => { band[1] = v; write(false); }, t('where.band_high')), 'MHz',
        removeButton(t, () => { bands.splice(index, 1); write(true); }))),
      h('div', { class: 'inline' },
        button('add', { onClick: suggest }, t('where.find_band'))),
      warn), t('where.band_help'), hint(t, 'help.head.frequency_range', { label: t('where.band') })),
    fold(t('where.taken', { n: taken.length }), false,
      h('ul', { class: 'taken' }, taken.map((o) => h('li', {},
        h('b', { text: o.name }), ` ${o.bands.map(([lo, hi]) => (lo === hi ? khzToMhz(lo) : `${khzToMhz(lo)}-${khzToMhz(hi)}`)).join(', ')} MHz`)))));
}

function hoursEditor({ model, t, changed, rerender }) {
  const head = model.head;
  const ranges = parseHours(sheet.value(head, 'listen'));
  const write = (structural) => {
    const text = formatHours(ranges);
    sheet.setValue(head, 'listen', text === 'always' ? null : text);
    changed();
    if (structural) rerender();
  };
  return row(t('where.hours'), (id) => h('div', { class: 'stack', id },
    ranges.length === 0 && h('p', { class: 'muted', text: t('where.always') }),
    ranges.map((range, index) => h('div', { class: 'inline' },
      timeRange(t, range, (v) => { ranges[index] = v; write(false); },
        { fromLabel: t('where.hours_start'), toLabel: t('where.hours_end') }),
      removeButton(t, () => { ranges.splice(index, 1); write(true); }))),
    button('add', { onClick: () => { ranges.push(['18:00', '21:00']); write(true); } },
      t('where.add_hours'))), t('where.hours_help'), hint(t, 'help.head.listen', { label: t('where.hours') }));
}

function locationEditor({ model, catalog, t, changed, rerender }) {
  const head = model.head;
  const current = sheet.value(head, 'location') ?? 'none';
  const options = (catalog.headerChoices('location') ?? [])
    .map((v) => withHint(t, 'help.head.location', choice(t, 'choice.location', v)));
  const coords = (sheet.value(head, 'coords') ?? '').split(',').map((v) => v.trim());
  const map = mapLink(t, () => ({ x: coords[0], y: coords[1], z: coords[2] }));
  const writeCoords = () => {
    sheet.setValue(head, 'coords', coords.every((v) => v !== '') ? coords.join(',') : null);
    changed();
    map.refresh();
  };
  const coord = (index, label) => h('input', { type: 'number', step: 1, class: 'num', value: coords[index] ?? '',
    'aria-label': label, onInput: (e) => { coords[index] = e.target.value; writeCoords(); } });
  return h('div', { class: 'form' },
    row(t('where.location'), () => radios('location', options, current, (v) => {
      sheet.setValue(head, 'location', v);
      if (v !== 'fixed') sheet.setValue(head, 'coords', null);
      changed();
      rerender();
    }), null, hint(t, 'help.head.location', { label: t('where.location'), choices: choiceTopics('help.head.location', options) })),
    current === 'fixed' && row(t('where.coords'), (id) => h('div', { class: 'inline', id },
      'x', coord(0, 'x'), 'y', coord(1, 'y'), 'z', coord(2, 'z'), map.el), t('where.coords_help'),
    hint(t, 'help.head.coords', { label: t('where.coords') })));
}

// Spontaneous call (E22-T07): one chance in N per game hour, and the text the voice says when the bridge writes none,
// written in the sheet (call=, %1 = frequency). A voice that already names a translation key (call_text=, voices of
// the mod) keeps it, shown in its place. The text field appears once calls are on (redrawn when the number is set).
function callEditor({ model, t, changed, rerender }) {
  const head = model.head;
  const oneIn = sheet.value(head, 'call_one_in') ?? '';
  const textKey = sheet.value(head, 'call_text') ? 'call_text' : 'call';
  return h('div', { class: 'form' },
    row(t('where.call_one_in'), (id) => h('input', { id, type: 'number', min: 0, max: 1000, step: 1, class: 'num',
      value: oneIn, onInput: (e) => {
        const v = e.target.value.trim();
        sheet.setValue(head, 'call_one_in', v === '' || v === '0' ? null : v);
        changed();
      }, onChange: () => rerender() }),
    t('where.call_one_in_help'), hint(t, 'help.head.call_one_in', { label: t('where.call_one_in') })),
    Number(oneIn) > 0 && row(t(`where.${textKey}`), (id) => textInput(id, sheet.value(head, textKey), (v) => {
      sheet.setValue(head, textKey, v.trim() === '' ? null : v);
      changed();
    }, { placeholder: t(`where.${textKey}_placeholder`) }), t(`where.${textKey}_help`),
    hint(t, `help.head.${textKey}`, { label: t(`where.${textKey}`) })));
}

export default {
  id: 'where',
  fields: ['frequencies', 'frequency_range', 'radio', 'listen', 'location', 'coords', 'call_one_in', 'call', 'call_text'],
  render(ctx) {
    const { model, catalog, t, changed } = ctx;
    const radio = (catalog.headerChoices('radio') ?? []).map((v) => withHint(t, 'help.head.radio', choice(t, 'choice.radio', v)));
    return h('div', { class: 'form' },
      h('p', { class: 'q', text: t('where.question') }),
      bandEditor(ctx),
      row(t('where.radio'), () => radios('radio', radio, sheet.value(model.head, 'radio') ?? 'any', (v) => {
        sheet.setValue(model.head, 'radio', v);
        changed();
      }), null, hint(t, 'help.head.radio', { label: t('where.radio'), choices: choiceTopics('help.head.radio', radio) })),
      hoursEditor(ctx),
      locationEditor(ctx),
      callEditor(ctx));
  },
};
