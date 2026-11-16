// Light checks of a sheet model for instant feedback, derived from the catalogue (ADR atelier-voix D03): required keys,
// closed choices, value shapes of the parameter kinds, references between sections. The game stays the only judge: a
// check never blocks a save, the page only shows it. Pure module.
//
// check(model, catalog, voiceId) -> [{key, args, where: {block: 'head' | <section kind> | 'prompt', id, field}}]
// `key` is an i18n message key, `args` its values.

import { categoryIds, categoryTypes } from './categories.js';
import * as sheet from './sheet.js';
import { isInteger, isTime, parseHours, parseList, parsePool, parseStockItem, sheetFrequency } from './values.js';

const ITEM_RE = /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/;
const SECTION_ID_RE = /^[a-z0-9_]{1,32}$/;

const count = (v) => isInteger(v) && Number(v) >= 0;
function range(v) {
  const [lo, hi, extra] = String(v).split('-').map((s) => s.trim());
  if (extra !== undefined || !count(lo)) return false;
  return hi === undefined || (count(hi) && Number(lo) <= Number(hi));
}

// Shape of a value by parameter kind (catalog.paramKinds); a kind missing here is left to the game.
export const KIND_CHECKS = {
  count: (v) => (count(v) ? null : 'check.bad_count'),
  range: (v) => (range(v) ? null : 'check.bad_range'),
  category: (v, ctx) => (ctx.categories.has(v) ? null : 'check.unknown_category'),
  place: (v, ctx) => (ctx.places.has(v) ? null : 'check.unknown_place'),
  places: (v, ctx) => {
    const list = parseList(v);
    if (list.length < 2) return 'check.too_few_places';
    return list.every((p) => ctx.places.has(p)) ? null : 'check.unknown_place';
  },
  item: (v) => (ITEM_RE.test(v) ? null : 'check.bad_item'),
  skill: (v, ctx) => (ctx.skills.has(v) ? null : 'check.unknown_skill'),
  text: (v) => (String(v).trim() ? null : 'check.empty_text'),
};

// Section key a mission needs when its type declares this voice set-up (catalog missionTypes[*].setups).
const SETUP_NEEDS = {
  aimAt: (mission) => (sheet.value(mission, 'target') ? null : 'check.needs_target'),
  dropAccepts: (mission, ctx) => (ctx.drops.size ? null : 'check.needs_drop'),
};

function checkKind(kind, value, ctx) {
  const rule = KIND_CHECKS[kind];
  return rule ? rule(String(value ?? '').trim(), ctx) : null;
}

function context(model, catalog) {
  const placeSections = sheet.sectionsOf(model, 'place');
  return {
    model,
    places: new Set(placeSections.map((s) => s.id)),
    drops: new Set(placeSections.filter((s) => parseList(sheet.value(s, 'use')).includes('drop')).map((s) => s.id)),
    missions: new Set(sheet.sectionsOf(model, 'mission').map((s) => s.id)),
    categories: new Set(categoryIds(model, catalog)),
    skills: new Set(catalog.skills()),
  };
}

// A required key said in plain words instead of "Missing: <key>": MISSING_KEYS[block][key] -> message key.
const MISSING_KEYS = { trade: { accept: 'check.no_accept' } };

function checkBlock(block, grammar, extraKeys, where, out) {
  const present = sheet.keys(block);
  for (const key of grammar.required) {
    if (!present.includes(key)) {
      out.push({ key: MISSING_KEYS[where.block]?.[key] ?? 'check.missing_key', args: { name: key },
        where: { ...where, field: key } });
    }
  }
  for (const key of present) {
    if (!grammar.keys.includes(key) && !extraKeys(key)) {
      out.push({ key: 'check.unknown_key', args: { name: key }, where: { ...where, field: key } });
    }
  }
  for (const [key, choices] of Object.entries(grammar.choices)) {
    for (const val of sheet.values(block, key).flatMap(parseList)) {
      if (!choices.includes(val)) {
        out.push({ key: 'check.bad_choice', args: { name: key, value: val }, where: { ...where, field: key } });
      }
    }
  }
}

// Where the voice is heard (E24-T01): the radio it needs (radio=, a free frequency drawn in its zone at each new game) or
// one fixed frequency (frequency=), exactly one of them; a fixed frequency on the step of every radio, inside their
// bounds, and never the fixed frequency of another voice.
function checkFrequency(head, catalog, voiceId, where, out) {
  const radio = sheet.value(head, 'radio');
  const text = sheet.value(head, 'frequency');
  const at = (field) => ({ ...where, field });
  if (!radio && !text) {
    out.push({ key: 'check.no_frequency', args: {}, where: at('radio') });
    return;
  }
  if (radio && text) out.push({ key: 'check.radio_and_frequency', args: {}, where: at('frequency') });
  if (!text) return;
  const khz = sheetFrequency(text);
  const { min, max, step } = catalog.frequencyBounds();
  if (khz === null || khz < min || khz > max || khz % step !== 0) {
    out.push({ key: 'check.bad_frequency', args: { value: text }, where: at('frequency') });
    return;
  }
  for (const other of catalog.fixedFrequencies(voiceId).filter((o) => o.khz === khz)) {
    out.push({ key: 'check.frequency_taken', args: { name: other.name }, where: at('frequency') });
  }
}

function checkHead(model, catalog, voiceId, out) {
  const head = model.head;
  const grammar = catalog.header();
  const where = { block: 'head', id: null };
  checkBlock(head, grammar, (key) => key.startsWith(grammar.budgetPrefix), where, out);
  checkFrequency(head, catalog, voiceId, where, out);
  if (parseHours(sheet.value(head, 'listen')).some(([from, to]) => !isTime(from) || !isTime(to) || from === to)) {
    out.push({ key: 'check.bad_hours', args: {}, where: { ...where, field: 'listen' } });
  }
  if (sheet.value(head, 'location') === 'fixed' && !sheet.value(head, 'coords')) {
    out.push({ key: 'check.missing_key', args: { name: 'coords' }, where: { ...where, field: 'coords' } });
  }
}

function checkSections(model, catalog, ctx, out) {
  const seen = new Set();
  for (const section of model.sections) {
    const where = { block: section.kind, id: section.id };
    const grammar = catalog.section(section.kind);
    if (!grammar) {
      out.push({ key: 'check.unknown_section', args: { name: section.kind }, where });
      continue;
    }
    if (grammar.hasId && !(section.id && SECTION_ID_RE.test(section.id))) {
      out.push({ key: 'check.bad_section_id', args: { name: section.kind, value: section.id ?? '' }, where });
    }
    const unique = `${section.kind} ${section.id}`;
    if (seen.has(unique)) out.push({ key: 'check.duplicate_section', args: { name: section.kind, value: section.id ?? '' }, where });
    seen.add(unique);
    const type = section.kind === 'mission' ? catalog.missionType(sheet.value(section, 'type')) : null;
    checkBlock(section, grammar, (key) => Boolean(type && key in type.params), where, out);
    SECTION_CHECKS[section.kind]?.(section, { catalog, ctx, type, where, out });
  }
}

function checkPlace(section, { where, out }) {
  const at = sheet.value(section, 'at');
  if (at !== null && !/^\s*\d+\s*,\s*\d+\s*,\s*-?\d+\s*$/.test(at)) {
    out.push({ key: 'check.bad_at', args: { value: at }, where: { ...where, field: 'at' } });
  }
}

function checkMission(section, { ctx, type, where, out }) {
  const typeName = sheet.value(section, 'type');
  if (typeName && !type) out.push({ key: 'check.unknown_type', args: { value: typeName }, where: { ...where, field: 'type' } });
  if (type) {
    for (const [key, kind] of Object.entries(type.params)) {
      const val = sheet.value(section, key);
      const problem = val === null ? null : checkKind(kind, val, ctx);
      if (problem) out.push({ key: problem, args: { name: key, value: val }, where: { ...where, field: key } });
    }
    for (const setup of type.setups) {
      const problem = SETUP_NEEDS[setup]?.(section, ctx);
      if (problem) out.push({ key: problem, args: {}, where: { ...where, field: setup } });
    }
  }
  const after = sheet.value(section, 'after');
  if (after !== null && (!ctx.missions.has(after) || after === section.id)) {
    out.push({ key: 'check.unknown_mission', args: { value: after }, where: { ...where, field: 'after' } });
  }
  const target = sheet.value(section, 'target');
  if (target !== null && !ctx.places.has(target)) {
    out.push({ key: 'check.unknown_place', args: { name: 'target', value: target }, where: { ...where, field: 'target' } });
  }
  const drops = sheet.value(section, 'drops');
  if (drops !== null && drops !== 'any') {
    for (const id of parseList(drops).filter((p) => !ctx.drops.has(p))) {
      out.push({ key: 'check.not_a_drop', args: { value: id }, where: { ...where, field: 'drops' } });
    }
  }
}

function checkRewards(section, { catalog, ctx, where, out }) {
  for (const row of parsePool(sheet.value(section, 'pool'))) {
    const kind = catalog.rewardKind(row.kind);
    const at = { ...where, field: 'pool' };
    if (!kind) {
      out.push({ key: 'check.unknown_reward', args: { value: row.kind }, where: at });
      continue;
    }
    const problem = kind.param ? checkKind(kind.param, row.param, ctx) : (row.param ? 'check.bad_pool' : null);
    if (problem) out.push({ key: problem, args: { name: row.kind, value: row.param }, where: at });
    if (!(isInteger(row.weight) && Number(row.weight) >= 1)) {
      out.push({ key: 'check.bad_weight', args: { name: row.kind, value: row.weight }, where: at });
    }
  }
}

// Problem of one accept= value (E23-T06), as RS_Persona.lua resolves it: an item needs a trade value, a category must
// exist and have at least one item with a trade value; null when the game takes it.
function acceptProblem(value, catalog, ctx) {
  if (ITEM_RE.test(value)) return catalog.isSellable(value) ? null : 'check.accept_not_sellable';
  const types = categoryTypes(ctx.model, catalog, value);
  if (!types) return 'check.accept_unknown_category';
  return types.some(catalog.isSellable) ? null : 'check.accept_no_value';
}

// Stock of a trader: the trade only sells an item with a sale value (catalog.sellable); any other line could never be
// offered (the game refuses every offer naming it). What the voice accepts as payment: only what has a trade value.
function checkTrade(section, { catalog, ctx, where, out }) {
  for (const { type } of sheet.values(section, 'item').map(parseStockItem)) {
    if (ITEM_RE.test(type) && !catalog.isSellable(type)) {
      out.push({ key: 'check.not_sellable', args: { value: type }, where: { ...where, field: 'item' } });
    }
  }
  for (const value of sheet.values(section, 'accept')) {
    const problem = acceptProblem(value, catalog, ctx);
    if (problem) out.push({ key: problem, args: { value }, where: { ...where, field: 'accept' } });
  }
}

// Extra checks of a section kind beyond its grammar; a kind missing here gets the grammar checks only.
const SECTION_CHECKS = { place: checkPlace, mission: checkMission, rewards: checkRewards, trade: checkTrade };

export function check(model, catalog, voiceId = null) {
  const out = [];
  const ctx = context(model, catalog);
  checkHead(model, catalog, voiceId, out);
  checkSections(model, catalog, ctx, out);
  const maxPlaces = catalog.sheet.maxPlaces;
  if (maxPlaces && ctx.places.size > maxPlaces) {
    out.push({ key: 'check.too_many_places', args: { value: maxPlaces }, where: { block: 'place', id: null } });
  }
  if (!sheet.promptText(model).trim()) out.push({ key: 'check.no_prompt', args: {}, where: { block: 'prompt', id: null } });
  return out;
}
