// Light checks of a sheet model for instant feedback, derived from the catalogue (ADR atelier-voix D03): required keys,
// closed choices, value shapes of the parameter kinds, references between sections. The game stays the only judge: a
// check never blocks a save, the page only shows it. Pure module.
//
// check(model, catalog, voiceId, shared) -> [{key, args, where: {block: 'head' | <section kind> | 'prompt', id, field}}]
// `key` is an i18n message key, `args` its values. `shared`: the shared places of personas/_places.txt (places.js
// list: [{id, kind}]) the voice may name (E25-T03).

import { categoryIds, categoryTypes } from './categories.js';
import { PLACE_REFS, ZONE } from './places.js';
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
  place: (v, ctx) => pointProblem(v, ctx),
  places: (v, ctx) => {
    const list = parseList(v);
    if (list.length < 2) return 'check.too_few_places';
    return list.map((p) => pointProblem(p, ctx)).find(Boolean) ?? null;
  },
  item: (v) => (ITEM_RE.test(v) ? null : 'check.bad_item'),
  skill: (v, ctx) => (ctx.skills.has(v) ? null : 'check.unknown_skill'),
  text: (v) => (String(v).trim() ? null : 'check.empty_text'),
};

// A shared place named by the voice: known, and a point where the player needs an exact spot (`points`, D05).
function placeProblem(id, ctx, points) {
  const place = ctx.places.get(id);
  if (!place) return 'check.unknown_place';
  return points && place.kind === ZONE ? 'check.place_is_zone' : null;
}
function pointProblem(id, ctx) {
  return placeProblem(id, ctx, true);
}

// Section key a mission needs when its type declares this voice set-up (catalog missionTypes[*].setups).
const SETUP_NEEDS = {
  dropAccepts: (mission) => (parseList(sheet.value(mission, 'drops')).length ? null : 'check.needs_drop'),
};

function checkKind(kind, value, ctx) {
  const rule = KIND_CHECKS[kind];
  return rule ? rule(String(value ?? '').trim(), ctx) : null;
}

function context(model, catalog, shared) {
  return {
    model,
    places: new Map((shared ?? []).map((p) => [p.id, p])),
    distances: new Set(catalog.distances()),
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
  const marks = parseList(sheet.value(head, 'marks'));
  const max = catalog.sheet.maxMarks;
  const at = { ...where, field: 'marks' };
  if (new Set(marks).size !== marks.length) out.push({ key: 'check.duplicate_mark', args: {}, where: at });
  if (max && marks.length > max) out.push({ key: 'check.too_many_marks', args: { value: max }, where: at });
}

// Every key of PLACE_REFS (places.js): a known shared place, a point where the player needs an exact spot (D05); a
// distance (near, far, very_far) is no place. The mission parameters of kind place / places go through KIND_CHECKS.
function checkPlaceRefs(model, ctx, out) {
  for (const ref of PLACE_REFS) {
    const owners = ref.block === 'head' ? [model.head] : sheet.sectionsOf(model, ref.block);
    for (const owner of owners) {
      for (const id of sheet.values(owner, ref.key).flatMap(parseList).filter((v) => !ctx.distances.has(v))) {
        const problem = placeProblem(id, ctx, ref.points);
        if (problem) {
          out.push({ key: problem, args: { name: ref.key, value: id },
            where: { block: ref.block, id: ref.block === 'head' ? null : owner.id, field: ref.key } });
        }
      }
    }
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
  // A building kind is drawn in a zone or around the player, never at a point (RS_Persona missionAim).
  const target = sheet.value(section, 'target');
  if (sheet.value(section, 'building') !== null && ctx.places.get(target)?.kind === 'point') {
    out.push({ key: 'check.building_needs_zone', args: {}, where: { ...where, field: 'building' } });
  }
}

function checkRewards(section, { catalog, ctx, where, out }) {
  const rows = parsePool(sheet.value(section, 'pool'));
  if (rows.some((row) => catalog.rewardKind(row.kind)?.place) && !sheet.value(section, 'cache_place')) {
    out.push({ key: 'check.needs_cache_place', args: {}, where: { ...where, field: 'cache_place' } });
  }
  for (const row of rows) {
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
const SECTION_CHECKS = { mission: checkMission, rewards: checkRewards, trade: checkTrade };

export function check(model, catalog, voiceId = null, shared = []) {
  const out = [];
  const ctx = context(model, catalog, shared);
  checkHead(model, catalog, voiceId, out);
  checkSections(model, catalog, ctx, out);
  checkPlaceRefs(model, ctx, out);
  if (!sheet.promptText(model).trim()) out.push({ key: 'check.no_prompt', args: {}, where: { block: 'prompt', id: null } });
  return out;
}
