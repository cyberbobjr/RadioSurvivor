// A numeric setting as named steps (charter rule 2, scales.js): one button per step in words, its number in the
// tooltip, and a closed "Exact value" panel holding the number itself. A value written by hand that is no step lights
// its nearest step and says "custom value"; the panel shows it. i18n: scale.<block>.<key>.<step> (+ .help).

import { h } from './dom.js';
import { scaleKey, scaleOf, stepOf } from './scales.js';
import { parseMargin, formatMargin } from './values.js';
import { button, cards, fold, numberInput } from './widgets.js';

// Editors of the exact value by kind of scale: {el, set(text)}; `onChange(text)` with the sheet text ('' = no line).
const EXACT_EDITORS = {
  number: (t, scale, value, onChange) => {
    const input = numberInput(value ?? '', (v) => onChange(v.trim()),
      { min: scale.min, max: scale.max, step: scale.step, inputmode: scale.step < 1 ? 'decimal' : 'numeric',
        'aria-label': t('scale.exact') });
    return { el: input, set: (text) => { input.value = text ?? ''; } };
  },
  // Margin "0.10-0.50" as "from [10] % to [50] %"; both empty: no line.
  margin: (t, scale, value, onChange) => {
    const current = parseMargin(value);
    const pct = (side, label) => numberInput(current[side], (v) => { current[side] = v; onChange(formatMargin(current)); },
      { min: 0, max: 100, step: 5, 'aria-label': label });
    const lo = pct('min', t('field.min'));
    const hi = pct('max', t('field.max'));
    const el = h('span', { class: 'inline' }, t('field.from'), lo, '%', t('field.to'), hi, '%');
    return { el, set: (text) => { Object.assign(current, parseMargin(text)); lo.value = current.min; hi.value = current.max; } };
  },
};

// The setting `key` of the block `block` (head, trade, mission), which has a scale in scales.js.
export function stepChoice(t, block, key, value, onChange, { id = null } = {}) {
  const scale = scaleOf(block, key);
  const prefix = scaleKey(block, key);
  let current = value ?? '';
  const pills = h('div', { role: 'group', class: scale.look === 'cards' ? 'steps' : 'chances steps', id, 'data-scale': prefix });
  const custom = h('small', { class: 'custom-chance', 'aria-live': 'polite' });
  const exact = EXACT_EDITORS[scale.exact ?? 'number'](t, scale, current, (text) => {
    current = text;
    onChange(text === '' ? null : text);
    draw();
  });
  const pick = (step) => { current = step.value ?? ''; exact.set(current); onChange(step.value); draw(); };
  function draw() {
    const at = stepOf(scale, current);
    custom.textContent = at && !at.exact ? t('scale.custom') : '';
    if (scale.look === 'cards') {
      pills.replaceChildren(cards(`${prefix}-${id ?? ''}`, scale.steps.map((step) => ({ value: step.id,
        label: t(`${prefix}.${step.id}`), help: t(`${prefix}.${step.id}.help`, {}, '') || null,
        icon: t(`${prefix}.${step.id}.icon`, {}, '') || null })), at?.step.id ?? '',
      (stepId) => pick(scale.steps.find((s) => s.id === stepId)), { class: 'compact' }));
      return;
    }
    pills.replaceChildren(...scale.steps.map((step) => {
      const on = at?.step === step;
      return button(on ? 'primary' : 'choice', { 'aria-pressed': String(on), 'data-step': step.id,
        title: t(`${prefix}.${step.id}.help`, {}, '') || null,
        onClick: () => pick(step) }, t(`${prefix}.${step.id}`));
    }));
  }
  draw();
  return h('div', { class: 'step-choice' }, pills, custom,
    fold(t('scale.exact'), false, h('div', { class: 'exact' }, exact.el)));
}
