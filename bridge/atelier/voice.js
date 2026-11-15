// What the assistant does to a sheet model: a new voice, its places, missions and reward pool. Pure module on top of
// sheet.js (syntax) and values.js (value shapes); the page (steps/*.js) and the node benches both use it.

import * as sheet from './sheet.js';
import { DEFAULT_CHANCE, formatAt, formatBands, formatList, formatPool, parseAt, parseList, parsePool } from './values.js';

const ID_SAFE = /[^a-z0-9_]+/g;

export function starterPrompt(name) {
  return `You are ${name}, a survivor who talks on the radio in July 1993, during the "Knox Event": a fast-spreading `
    + 'infection turned people in Knox County, Kentucky, into violent, undead "zombies", and the army sealed the area. '
    + 'You cannot see the callers and you do not know where they are.\n\nRules:\n'
    + '- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.\n'
    + '- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown. End each transmission with '
    + '"Over."\n- Answer in the same language the caller uses.';
}

// Empty voice: the head the format requires, a free band, a starter prompt to rewrite.
export function newVoice({ id, name, band, format = '1' }) {
  const model = sheet.parse('');
  model.tail = [];
  const head = model.head;
  sheet.setValue(head, 'format', format);
  sheet.setValue(head, 'id', id);
  sheet.setValue(head, 'name', name || id);
  sheet.setValue(head, 'language', 'en');
  if (band) sheet.setValue(head, 'frequency_range', formatBands([band]));
  sheet.setValue(head, 'radio', 'any');
  sheet.setValue(head, 'location', 'none');
  sheet.setValue(head, 'actions', 'say');
  sheet.setValue(head, 'state', 'active');
  sheet.setPromptText(model, starterPrompt(name || id));
  return model;
}

export function slug(text, fallback = 'item') {
  const out = String(text ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(ID_SAFE, '_').replace(/^_+|_+$/g, '').slice(0, 24);
  return /^[a-z]/.test(out) ? out : `${fallback}${out ? `_${out}` : ''}`.slice(0, 24);
}

export function uniqueId(model, kind, base) {
  const taken = new Set(sheet.sectionsOf(model, kind).map((s) => s.id));
  if (!taken.has(base)) return base;
  for (let n = 2; ; n += 1) if (!taken.has(`${base}_${n}`)) return `${base}_${n}`;
}

// --- places ---------------------------------------------------------------------------------------------------------
export function places(model) {
  return sheet.sectionsOf(model, 'place').map((s) => ({
    section: s, id: s.id, label: sheet.value(s, 'label') ?? '', at: parseAt(sheet.value(s, 'at')),
    uses: parseList(sheet.value(s, 'use')),
  }));
}

export function addPlace(model, { id, label = '', at = null, uses = [] } = {}) {
  const created = sheet.addSection(model, 'place', uniqueId(model, 'place', id || slug(label, 'place')));
  setPlace(created, { label, at, uses });
  return created;
}

export function setPlace(section, { label, at, uses }) {
  if (at !== undefined && at !== null) sheet.setValue(section, 'at', formatAt(at));
  if (label !== undefined) sheet.setValue(section, 'label', label);
  if (uses !== undefined) sheet.setValue(section, 'use', formatList(uses));
}

// --- missions -------------------------------------------------------------------------------------------------------
export function missions(model) {
  return sheet.sectionsOf(model, 'mission');
}

export function addMission(model, type, values = {}) {
  const created = sheet.addSection(model, 'mission', uniqueId(model, 'mission', slug(values.id || type, 'mission')));
  sheet.setValue(created, 'type', type);
  for (const [key, val] of Object.entries(values)) if (key !== 'id') sheet.setValue(created, key, val);
  return created;
}

// Draw weight of a mission. The game reads 1 when weight= is missing: with no weight anywhere all missions are equal
// ("normal"); once one mission has a weight, the missing ones really weigh 1.
export function missionWeight(model, mission) {
  const own = sheet.value(mission, 'weight');
  if (own !== null) return own;
  return missions(model).some((m) => sheet.value(m, 'weight') !== null) ? '1' : DEFAULT_CHANCE;
}

// Sets the weight of one mission and writes the "normal" weight on the missions that had none, so that their chances
// stay what the page showed.
export function setMissionWeight(model, mission, weight) {
  const shown = missions(model).map((m) => [m, missionWeight(model, m)]);
  for (const [other, current] of shown) if (other !== mission) sheet.setValue(other, 'weight', current);
  sheet.setValue(mission, 'weight', weight);
}

// --- reward pool ----------------------------------------------------------------------------------------------------
export function pool(model) {
  const rewards = sheet.section(model, 'rewards');
  return rewards ? parsePool(sheet.value(rewards, 'pool')) : [];
}

// Rows of the pool written to [rewards] pool=; no row: no [rewards] section (the voice then gives map marks).
export function setPool(model, rows) {
  const text = formatPool(rows);
  let rewards = sheet.section(model, 'rewards');
  if (!text) {
    if (rewards) sheet.removeSection(model, rewards);
    return;
  }
  if (!rewards) rewards = sheet.addSection(model, 'rewards');
  sheet.setValue(rewards, 'pool', text);
}
