// Named steps of the numeric settings (E24-T02, charter rule 2: a number of the game is a choice in words). One table,
// the only place that maps a step to the value written in the sheet; the page shows the step's words (i18n
// scale.<scale>.<step>, its number in .help) and keeps the exact number in a closed "Exact value" panel.
// `look: 'cards'` shows the steps as cards with their help (the margin, user decision 2026-11-16), else buttons.
// A step's `value` is what the sheet gets (null: no line, the game's default), `n` the number it stands for (to find
// the nearest step of a hand-written value). Values come from the reader and the defaults of the mod:
// - head.call_one_in: one chance in N per game hour (RS_Persona MAX_CALL_ONE_IN 1000; shipped voices 3, 6, 8);
// - trade.every_days: days between two visits (1 to 28, RS_Persona MAX_EVERY_DAYS; shipped 4 to 8);
// - trade.delay_hours: game hours out of sight (0 to 48; default 1, RS_TradeExchange DELAY_HOURS);
// - trade.margin: lowest-highest share the trader keeps (0 to 1; default 0.10-0.50, RS_Persona TRADE_MARGIN);
// - mission.collect_hours: game hours before the goods are picked up (default 6, CA_Missions);
// - mission.hours: game hours of a watch (1 to 24, default 2, CA_MissionConfig watch).
// Pure module.

import { parseMargin } from './values.js';

// Middle of a margin "0.10-0.50" (its place between the cards), NaN when it is not one.
const marginMiddle = (text) => {
  const { min, max } = parseMargin(text);
  return min === '' || max === '' ? NaN : (Number(min) + Number(max)) / 200;
};

export const SCALES = {
  'scale.head.call_one_in': { min: 0, max: 1000, step: 1, steps: [
    { id: 'never', value: null, n: 0 }, { id: 'rare', value: '12' }, { id: 'sometimes', value: '6' },
    { id: 'often', value: '3' }] },
  'scale.trade.every_days': { min: 1, max: 28, step: 1, steps: [
    { id: 'daily', value: '1' }, { id: 'few_days', value: '3' }, { id: 'weekly', value: '7' },
    { id: 'two_weeks', value: '14' }, { id: 'monthly', value: '28' }] },
  'scale.trade.delay_hours': { min: 0, max: 48, step: 0.5, steps: [
    { id: 'now', value: '0' }, { id: 'hour', value: null, n: 1 }, { id: 'hours', value: '4' },
    { id: 'day', value: '24' }] },
  'scale.trade.margin': { exact: 'margin', look: 'cards', toNumber: marginMiddle, steps: [
    { id: 'generous', value: '0.05-0.25' }, { id: 'fair', value: null, n: 0.3 }, { id: 'greedy', value: '0.30-0.80' }] },
  'scale.mission.collect_hours': { min: 1, max: 48, step: 1, steps: [
    { id: 'soon', value: '2' }, { id: 'normal', value: null, n: 6 }, { id: 'late', value: '12' },
    { id: 'day', value: '24' }] },
  'scale.mission.hours': { min: 1, max: 24, step: 1, steps: [
    { id: 'short', value: '1' }, { id: 'normal', value: null, n: 2 }, { id: 'long', value: '6' },
    { id: 'night', value: '12' }] },
};

const numberOf = (scale, text) => (scale.toNumber ?? Number)(text);
const stepNumber = (scale, step) => step.n ?? numberOf(scale, step.value);

// {step, exact} of the sheet value `text` (null or '' = no line): the step writing exactly it, else the nearest step by
// number (exact: false, the exact panel shows the number); null when the value is empty and no step means "no line".
export function stepOf(scale, text) {
  const raw = text === null || text === undefined ? '' : String(text).trim();
  if (raw === '') {
    const none = scale.steps.find((s) => s.value === null);
    return none ? { step: none, exact: true } : null;
  }
  const same = scale.steps.find((s) => s.value === raw);
  if (same) return { step: same, exact: true };
  const n = numberOf(scale, raw);
  if (!Number.isFinite(n)) return null;
  let best = null;
  for (const step of scale.steps) {
    const distance = Math.abs(stepNumber(scale, step) - n);
    if (!best || distance < best.distance) best = { step, distance };
  }
  return { step: best.step, exact: best.distance < 1e-9 };
}

// Scale of a setting: SCALES[`scale.<block>.<key>`] (also the i18n prefix of its steps) or null (the setting keeps its
// own field).
export const scaleKey = (block, key) => `scale.${block}.${key}`;
export const scaleOf = (block, key) => SCALES[scaleKey(block, key)] ?? null;
