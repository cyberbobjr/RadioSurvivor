// Step 2, where and when: the radio the player needs (E24-T01), listening hours, location on the map, spontaneous call.

import { inputPropose } from '../ai.js';
import { h } from '../dom.js';
import { choiceTopics, hint } from '../help.js';
import { squareEditor } from '../maplink.js';
import * as sheet from '../sheet.js';
import { formatHours, khzToMhz, mhzToKhz, parseHours, sheetFrequency } from '../values.js';
import { stepChoice } from '../stepchoice.js';
import { button, cards, choice, fold, freqText, removeButton, row, switchBox, textInput, timeRange } from '../widgets.js';

// First frequency of the zone of `level` that no other voice holds as its fixed frequency: what the field shows when
// the switch "choose the frequency myself" is turned on.
function firstFreeFrequency(catalog, level, voiceId) {
  const taken = new Set(catalog.fixedFrequencies(voiceId).map((o) => o.khz));
  const { step } = catalog.frequencyBounds();
  for (const [low, high] of catalog.radioLevels().find((l) => l.id === level)?.zones ?? []) {
    for (let khz = low; khz <= high; khz += step) if (!taken.has(khz)) return khz;
  }
  return null;
}

// The radio levels as big cards: an emoji, a plain name, who hears the voice. Picking one writes radio=<level>; the
// game draws a free frequency of its zone at each new game (RS_Personas).
function radioCards({ model, catalog, t, changed, rerender }, id) {
  const head = model.head;
  const levels = catalog.radioLevels();
  const current = sheet.value(head, 'radio') ?? levels[0]?.id;
  return h('div', { id, class: 'radio-cards', role: 'radiogroup', 'aria-label': t('where.radio') },
    levels.map((level) => h('label', { class: 'radio-card', 'data-level': level.id },
      h('input', { type: 'radio', name: 'radio-level', value: level.id, checked: level.id === current,
        onChange: () => { sheet.setValue(head, 'radio', level.id); changed(); rerender(); } }),
      h('span', { class: 'radio-icon', 'aria-hidden': 'true', text: t(`radio.${level.id}.icon`) }),
      h('b', { text: t(`radio.${level.id}.name`) }),
      h('small', { text: t(`radio.${level.id}.who`) }))));
}

// One fixed frequency (frequency=, MHz) with a live badge naming the radio it needs and a warning when another voice
// already holds it.
function fixedFrequency({ model, catalog, t, voiceId, changed }) {
  const head = model.head;
  const bounds = catalog.frequencyBounds();
  const badge = h('p', { class: 'radio-badge', 'aria-live': 'polite' });
  const warn = h('div', { class: 'warnline', 'aria-live': 'polite' });
  const refresh = (text) => {
    const khz = sheetFrequency(text);
    const level = catalog.frequencyLevel(text);
    badge.textContent = level
      ? t('where.badge', { icon: t(`radio.${level}.icon`), name: t(`radio.${level}.name`) })
      : t('where.badge_none', { min: khzToMhz(bounds.min), max: khzToMhz(bounds.max), step: khzToMhz(bounds.step) });
    badge.dataset.level = level ?? '';
    const names = catalog.fixedFrequencies(voiceId).filter((o) => o.khz === khz).map((o) => o.name);
    warn.textContent = names.length ? t('where.fixed_taken', { names: names.join(', ') }) : '';
  };
  const input = h('input', { type: 'number', min: khzToMhz(bounds.min), max: khzToMhz(bounds.max),
    step: khzToMhz(bounds.step), class: 'num', value: sheet.value(head, 'frequency') ?? '',
    onInput: (e) => {
      const khz = mhzToKhz(e.target.value);
      const text = khz === null ? e.target.value.trim() : khzToMhz(khz);
      sheet.setValue(head, 'frequency', text === '' ? null : text);
      changed();
      refresh(text);
    } });
  refresh(sheet.value(head, 'frequency'));
  return row(t('where.fixed'), (id) => h('div', { class: 'stack' },
    h('div', { class: 'inline' }, Object.assign(input, { id }), 'MHz', badge), warn),
  t('where.fixed_help'), hint(t, 'help.head.frequency', { label: t('where.fixed') }));
}

// Where the voice is heard: the radio cards, or, behind a switch, one fixed frequency. Exactly one of radio= and
// frequency= is written; the switch carries the choice over (the radio a fixed frequency needs, or the first free
// frequency of the chosen radio).
function radioEditor(ctx) {
  const { model, catalog, t, voiceId, changed, rerender } = ctx;
  const head = model.head;
  const fixed = sheet.value(head, 'frequency') != null;
  const levels = catalog.radioLevels();
  const toggle = (on) => {
    if (on) {
      const khz = firstFreeFrequency(catalog, sheet.value(head, 'radio') ?? levels[0]?.id, voiceId);
      sheet.setValue(head, 'frequency', khz === null ? null : khzToMhz(khz));
      sheet.setValue(head, 'radio', null);
    } else {
      sheet.setValue(head, 'radio', catalog.levelOf(sheetFrequency(sheet.value(head, 'frequency'))) ?? levels[0]?.id);
      sheet.setValue(head, 'frequency', null);
    }
    changed();
    rerender();
  };
  const choices = levels.map((l) => ({ label: t(`radio.${l.id}.name`), topic: `help.head.radio.${l.id}` }));
  return h('div', { class: 'form radio-editor' },
    row(t('where.radio'), (id) => (fixed ? h('p', { id, class: 'muted', text: t('where.radio_fixed') }) : radioCards(ctx, id)),
      fixed ? null : t('where.radio_help'), hint(t, 'help.head.radio', { label: t('where.radio'), choices })),
    switchBox(t('where.fixed_toggle'), fixed, toggle, { id: 'fixed-frequency' }),
    fixed && fixedFrequency(ctx));
}

// Listening hours (E24-T02): three ready-made choices as cards (always, at night, by day) and "custom hours" holding
// the time ranges. HOUR_PRESETS is the only place that maps a card to listen= (null: no line, always).
const HOUR_PRESETS = [{ id: 'always', value: null }, { id: 'night', value: '20:00-06:00' }, { id: 'day', value: '08:00-20:00' }];
const CUSTOM = 'custom';
const CUSTOM_START = '18:00-21:00';

function hoursEditor({ model, t, changed, rerender, ui }) {
  const head = model.head;
  const text = sheet.value(head, 'listen');
  const preset = HOUR_PRESETS.find((p) => (p.value ?? 'always') === (text ?? 'always'));
  const current = ui.hours_custom || !preset ? CUSTOM : preset.id;
  const ranges = parseHours(text);
  const write = (structural) => {
    const out = formatHours(ranges);
    sheet.setValue(head, 'listen', out === 'always' ? null : out);
    changed();
    if (structural) rerender();
  };
  const options = [...HOUR_PRESETS.map((p) => p.id), CUSTOM].map((id) => ({ value: id, label: t(`where.hours.${id}`),
    help: t(`where.hours.${id}.help`), icon: t(`where.hours.${id}.icon`) }));
  const pick = (id) => {
    ui.hours_custom = id === CUSTOM;
    const chosen = HOUR_PRESETS.find((p) => p.id === id);
    if (chosen) sheet.setValue(head, 'listen', chosen.value);
    else if (!text) sheet.setValue(head, 'listen', CUSTOM_START);
    changed();
    rerender();
  };
  return row(t('where.hours'), (id) => h('div', { class: 'stack', id },
    cards('listen', options, current, pick),
    current === CUSTOM && h('div', { class: 'stack custom-hours' },
      ranges.map((range, index) => h('div', { class: 'inline' },
        timeRange(t, range, (v) => { ranges[index] = v; write(false); },
          { fromLabel: t('where.hours_start'), toLabel: t('where.hours_end') }),
        removeButton(t, () => { ranges.splice(index, 1); write(true); }))),
      button('add', { onClick: () => { ranges.push(CUSTOM_START.split('-')); write(true); } }, t('where.add_hours')))),
  null, hint(t, 'help.head.listen', { label: t('where.hours') }));
}

// Where the voice is on the map: cards, then the square (x, y, floor) with the map link when she is at a fixed place
// (user decision 2026-11-16: coordinates entered as before, fields, map link and places recorded in game).
function locationEditor({ model, catalog, t, changed, rerender, toast }) {
  const head = model.head;
  const current = sheet.value(head, 'location') ?? 'none';
  const options = (catalog.headerChoices('location') ?? []).map((v) => ({ ...choice(t, 'choice.location', v),
    icon: t(`choice.location.${v}.icon`, {}, '') || null }));
  const [x, y, z] = (sheet.value(head, 'coords') ?? ',,0').split(',').map((v) => v.trim());
  const writeCoords = (square) => {
    const coords = [square.x, square.y, square.z].map((v) => String(v ?? '').trim());
    sheet.setValue(head, 'coords', coords.every((v) => v !== '') ? coords.join(',') : null);
    changed();
  };
  return h('div', { class: 'form' },
    row(t('where.location'), (id) => cards('location', options, current, (v) => {
      sheet.setValue(head, 'location', v);
      if (v !== 'fixed') sheet.setValue(head, 'coords', null);
      changed();
      rerender();
    }, { id }), null, hint(t, 'help.head.location', { label: t('where.location'), choices: choiceTopics('help.head.location', options) })),
    current === 'fixed' && row(t('where.coords'), (id) => squareEditor(t, { x, y, z }, writeCoords, { id, toast }),
      t('where.coords_help'),
    hint(t, 'help.head.coords', { label: t('where.coords') })));
}

// Spontaneous call (E22-T07): how often the voice calls by itself, as named steps (scales.js head.call_one_in), and
// the text she says when the bridge writes none (call=, the frequency as a word on screen). A voice that already
// names a translation key (call_text=, voices of the mod) keeps it in the closed advanced panel.
function callEditor(ctx) {
  const { model, t, changed, rerender } = ctx;
  const head = model.head;
  const calls = Number(sheet.value(head, 'call_one_in') ?? 0) > 0;
  const own = sheet.value(head, 'call_text');
  return h('div', { class: 'form' },
    row(t('where.call_one_in'), (id) => stepChoice(t, 'head', 'call_one_in', sheet.value(head, 'call_one_in'), (v) => {
      sheet.setValue(head, 'call_one_in', v);
      changed();
      if ((Number(v ?? 0) > 0) !== calls) rerender();
    }, { id }), t('where.call_one_in_help'), hint(t, 'help.head.call_one_in', { label: t('where.call_one_in') })),
    calls && !own && row(t('where.call'), (id) => {
      const call = freqText(t, sheet.value(head, 'call'), (v) => {
        sheet.setValue(head, 'call', v.trim() === '' ? null : v);
        changed();
      }, { id, maxlength: 200, placeholder: t('where.call_placeholder') });
      call.el.append(inputPropose(ctx, 'call', call.input, { freqWord: t('freq.word') }));
      return call.el;
    }, t('where.call_help'),
    hint(t, 'help.head.call', { label: t('where.call') })),
    own && fold(t('section.advanced'), false, h('p', { class: 'help', text: t('section.advanced_help') }),
      row(t('where.call_text'), (id) => textInput(id, own, (v) => {
        sheet.setValue(head, 'call_text', v.trim() === '' ? null : v);
        changed();
      }, { spellcheck: 'false' }), null, hint(t, 'help.head.call_text', { label: t('where.call_text') }))));
}

// One question of the step: its title, then its form (charter rule 4).
const part = (title, ...children) => h('section', { class: 'question' }, h('h3', { text: title }), ...children);

export default {
  id: 'where',
  fields: ['radio', 'frequency', 'listen', 'location', 'coords', 'call_one_in', 'call', 'call_text'],
  render(ctx) {
    const { t } = ctx;
    return h('div', { class: 'form' },
      part(t('where.q_radio'), radioEditor(ctx)),
      part(t('where.q_hours'), hoursEditor(ctx)),
      part(t('where.q_location'), locationEditor(ctx)),
      part(t('where.q_call'), callEditor(ctx)));
  },
};
