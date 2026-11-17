// Building blocks shared by the steps of the assistant: buttons, labelled rows, editable lists, check boxes, panels,
// the three-level chance control. Their look is Pico CSS (vendor/pico.min.css) set by theme.css: a button only names
// its role here, never a colour or a size.

import { h, uid } from './dom.js';
import { CHANCES, chanceLevel, freqToScreen, freqToSheet } from './values.js';

// Role of a button -> Pico classes (theme.css gives the colours of primary, secondary, contrast and danger).
const BUTTON_KINDS = {
  primary: '',                         // the main action of a place: save, next, create
  neutral: 'outline contrast',         // other actions
  add: 'outline secondary add',        // "+ Add ..."
  ai: 'outline secondary',             // the bridge's AI
  danger: 'outline danger',            // delete, remove
  icon: 'outline contrast icon',       // small square button: remove a line, move it up
  choice: 'outline contrast',          // a choice not taken in a group of choices
};

// A button of a role (BUTTON_KINDS); `attrs.class` adds hook classes for the page or its tests.
export function button(kind, attrs = {}, ...children) {
  const classes = [BUTTON_KINDS[kind] ?? '', attrs.class ?? ''].join(' ').trim();
  return h('button', { type: 'button', ...attrs, class: classes || null }, ...children);
}

// Small "✕" button that removes something (`label`: its accessible name, "Remove" by default).
export function removeButton(t, onClick, label = null) {
  const name = label ?? t('field.remove');
  return button('icon', { title: name, 'aria-label': name, onClick }, '✕');
}

// Label (+ its "?" help button, help.js) + control (+ help line). `control` is a function receiving the id to give to
// its first input.
export function row(label, control, help = null, hintButton = null) {
  const id = uid();
  return h('div', { class: 'row' },
    h('div', { class: 'lab' }, h('label', { for: id }, label), hintButton),
    h('div', { class: 'ctl' }, control(id), help && h('p', { class: 'help', text: help })));
}

export function textInput(id, value, onInput, attrs = {}) {
  return h('input', { id, type: 'text', value: value ?? '', ...attrs, onInput: (e) => onInput(e.target.value) });
}

// A text field with its live count "12 / 48" (charter: limits said, never in bytes): {input, counter}.
export function countedInput(id, value, max, onInput, attrs = {}) {
  const counter = h('small', { class: 'counter', 'aria-live': 'polite' });
  const show = (text) => { counter.textContent = `${[...String(text ?? '')].length} / ${max}`; };
  const input = textInput(id, value, (v) => { show(v); onInput(v); }, { maxlength: max, ...attrs });
  show(value);
  return { input, counter };
}

// Editable list of sentences (item=, text=...): one line each, add, remove. Redraws itself only, so a new empty
// line stays on screen until it is filled (the sheet keeps no empty value).
export function listEditor(t, values, onChange, placeholder = '') {
  const list = [...values];
  const box = h('div', { class: 'stack' });
  const draw = (focusIndex = -1) => {
    box.replaceChildren(
      ...list.map((text, index) => h('div', { class: 'inline grow' },
        h('input', { type: 'text', value: text, placeholder, 'aria-label': placeholder || t('list.line', { n: index + 1 }),
          onInput: (e) => { list[index] = e.target.value; onChange(list); } }),
        removeButton(t, () => { list.splice(index, 1); onChange(list); draw(); }))),
      button('add', { onClick: () => { list.push(''); draw(list.length - 1); } }, t('list.add')));
    if (focusIndex >= 0) box.querySelectorAll('input')[focusIndex]?.focus();
  };
  draw();
  return box;
}

// Editable list of structured lines (trader stock, loot lists, lots): `draw(item, index, change, list)` returns the
// cells of one line (`list`: every line now) (theme.css lays every line of a list on the same grid), `blank()` a new line, `write(items)` stores them.
// `tools(addLines, list)` gives more buttons next to "+ Add" (the item browser), `addLines(items)` adding several lines
// at once, `list` the lines now. Without `blank` there is no "+ Add" (a list of items: its lines come from the item
// browser only). Redraws its lines only: the buttons under them stay (and keep the focus).
export function lineEditor(t, items, { draw, blank = null, write, addLabel = null, tools = null }) {
  const list = items.map((item) => ({ ...item }));
  const rows = h('div', { class: 'stack' });
  const redraw = (focusLast = false) => {
    rows.replaceChildren(...list.map((item, index) => h('div', { class: 'line' },
      draw(item, index, () => write(list), list),
      removeButton(t, () => { list.splice(index, 1); write(list); redraw(); }))));
    if (focusLast) rows.querySelector('.line:last-of-type input, .line:last-of-type select')?.focus();
  };
  const addLines = (more) => { list.push(...more); write(list); redraw(); };
  redraw();
  return h('div', { class: 'stack lines' }, rows,
    h('div', { class: 'line-tools' },
      blank && button('add', { onClick: () => { list.push(blank()); write(list); redraw(true); } }, addLabel),
      tools && tools(addLines, list)));
}

// Check boxes of `options` [{value, label, help, title, hint, locked}] (hint: "?" button of help.js; title: the tooltip,
// the help by default; locked: always ticked, cannot be unticked), `selected` a list of values.
export function checkboxes(options, selected, onChange, attrs = {}) {
  const chosen = new Set(selected);
  return h('div', { class: 'checks', ...attrs },
    options.map((o) => h('label', { class: 'check', title: o.title ?? o.help ?? null, 'data-value': o.value },
      h('input', { type: 'checkbox', checked: chosen.has(o.value) || o.locked, disabled: o.locked, onChange: (e) => {
        if (e.target.checked) chosen.add(o.value); else chosen.delete(o.value);
        onChange(options.map((x) => x.value).filter((v) => chosen.has(v)).concat([...chosen].filter((v) => !options.some((x) => x.value === v))));
      } }),
      h('span', {}, h('b', { text: o.label }), o.help && h('small', { text: o.help })), o.hint ?? null)));
}

// Radio buttons of `options` [{value, label, help, hint}].
export function radios(name, options, current, onChange) {
  return h('div', { class: 'checks', role: 'radiogroup' },
    options.map((o) => h('label', { class: 'check' },
      h('input', { type: 'radio', name, value: o.value, checked: o.value === current,
        onChange: () => onChange(o.value) }),
      h('span', {}, h('b', { text: o.label }), o.help && h('small', { text: o.help })), o.hint ?? null)));
}

// How often something is drawn, in three words (values.js CHANCES: rarely 1, normally 2, often 4) instead of a number.
// A weight that is none of them shows as "Custom (n)" and stays as it is until another choice is picked.
export function chanceChoice(t, weight, onChange, attrs = {}) {
  let current = String(weight ?? '');
  const group = h('div', { role: 'group', class: 'chances', ...attrs });
  const custom = h('span', { class: 'custom-chance', 'aria-live': 'polite' });
  const draw = () => {
    const level = chanceLevel(current);
    group.replaceChildren(...CHANCES.map((c) => button(level === c.level ? 'primary' : 'choice', {
      'aria-pressed': String(level === c.level), 'data-chance': c.level,
      onClick: () => { current = c.weight; onChange(c.weight); draw(); },
    }, t(`chance.${c.level}`))));
    custom.textContent = level === null && current !== '' ? t('chance.custom', { n: current }) : '';
  };
  draw();
  return h('div', { class: 'chance-choice' }, group, custom);
}

export function fold(title, open, ...children) {
  return h('details', { class: 'fold', open }, h('summary', { text: title }), ...children);
}

// Option of a closed choice: plain words from i18n "<prefix>.<value>" (+ ".help"), the raw value otherwise.
export function choice(t, prefix, value, fallbackHelp = null) {
  return { value, label: t(`${prefix}.${value}`, {}, value), help: t(`${prefix}.${value}.help`, {}, fallbackHelp ?? '') || null };
}

// Number field; `attrs` sets min, max, step, aria-label...
export function numberInput(value, onInput, attrs = {}) {
  return h('input', { type: 'number', min: 0, step: 1, inputmode: 'numeric', class: 'num', value: value ?? '', ...attrs,
    onInput: (e) => onInput(e.target.value) });
}

// On / off switch (Pico draws a checkbox with role="switch" as a switch) with its label.
export function switchBox(label, checked, onChange, attrs = {}) {
  return h('label', { class: 'switch' },
    h('input', { type: 'checkbox', role: 'switch', checked, ...attrs, onChange: (e) => onChange(e.target.checked) }),
    h('span', { text: label }));
}

// Closed choice as big cards (charter rule 7): `options` [{value, label, help, icon, hint}], one picked. `name` groups the
// radio inputs; `attrs` goes to the group (id, aria-label, class).
export function cards(name, options, current, onChange, attrs = {}) {
  return h('div', { role: 'radiogroup', ...attrs, class: `choice-cards ${attrs.class ?? ''}`.trim() },
    options.map((o) => h('label', { class: 'choice-card', 'data-value': o.value, title: o.title ?? null },
      h('input', { type: 'radio', name, value: o.value, checked: o.value === current, onChange: () => onChange(o.value) }),
      o.icon && h('span', { class: 'card-icon', 'aria-hidden': 'true', text: o.icon }),
      h('b', { text: o.label }), o.help && h('small', { text: o.help }), o.hint ?? null)));
}

// A whole number with "-" and "+" buttons (charter rule 7: a quantity is a stepper). Empty stays empty until a button
// is pressed (`emptyLabel` says what empty means, e.g. "no limit").
export function stepper(value, onChange, { min = 0, max = 999, label, emptyLabel = null, id = null } = {}) {
  const input = h('input', { type: 'number', min, max, step: 1, inputmode: 'numeric', class: 'num', id,
    value: value ?? '', placeholder: emptyLabel ?? '', 'aria-label': label,
    onInput: (e) => onChange(e.target.value.trim()) });
  const move = (delta) => {
    const now = input.value.trim() === '' ? (delta > 0 ? min - 1 : min + 1) : Number(input.value);
    const next = Math.max(min, Math.min(max, now + delta));
    input.value = String(next);
    onChange(input.value);
  };
  return h('span', { class: 'stepper' },
    h('button', { type: 'button', class: 'outline secondary step-btn', 'aria-label': `${label} -`, onClick: () => move(-1) }, '−'),
    input,
    h('button', { type: 'button', class: 'outline secondary step-btn', 'aria-label': `${label} +`, onClick: () => move(1) }, '+'));
}

// "Between [n] and [m]": a quantity drawn by the game ("2-4", or "3" for always 3) as two steppers in words.
export function rangeStepper(t, value, onChange, { min = 0, max = 999, id = null } = {}) {
  const [lo, hi] = String(value ?? '').split('-').map((v) => v.trim());
  const current = { min: lo ?? '', max: hi ?? lo ?? '' };
  const write = () => onChange(current.max === '' || current.max === current.min ? current.min : `${current.min}-${current.max}`);
  return h('span', { class: 'inline range' }, t('field.between'),
    stepper(current.min, (v) => { current.min = v; write(); }, { min, max, label: t('field.min'), id }),
    t('field.and'),
    stepper(current.max, (v) => { current.max = v; write(); }, { min, max, label: t('field.max') }));
}

// A text the players read where the voice's frequency appears (call=, note lines): the sheet's %1 is shown as the word
// t('freq.word') and the button "Add my frequency" puts it at the cursor (charter rule 3: no symbol to type).
// `onChange(sheetText)`; returns {el, input}.
export function freqText(t, value, onChange, attrs = {}) {
  const word = t('freq.word');
  const input = h('input', { type: 'text', ...attrs, value: freqToScreen(value, word),
    onInput: (e) => onChange(freqToSheet(e.target.value, word)) });
  const add = button('add', { class: 'freq-add', onClick: () => {
    const at = input.selectionStart ?? input.value.length;
    input.value = `${input.value.slice(0, at)}${word}${input.value.slice(input.selectionEnd ?? at)}`;
    input.focus();
    onChange(freqToSheet(input.value, word));
  } }, t('freq.add'));
  return { el: h('div', { class: 'inline grow' }, input, add), input };
}

// "from [time] to [time]": `range` [from, to] in HH:MM, `onChange(range)` at each change.
export function timeRange(t, range, onChange, { id = null, fromLabel, toLabel } = {}) {
  const current = [...range];
  const time = (index, label, attrs = {}) => h('input', { type: 'time', value: current[index], step: 60, 'aria-label': label,
    ...attrs, onInput: (e) => { current[index] = e.target.value; onChange([...current]); } });
  return h('span', { class: 'inline' }, t('field.from'), time(0, fromLabel, { id }), t('field.to'), time(1, toLabel));
}
