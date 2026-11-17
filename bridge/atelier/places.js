// Shared places of every voice (E25-T03, ADR lieux communs D02, D05-D07): the file personas/_places.txt read and
// written by the "Places" tab, and where a voice names a place. Pure module on top of sheet.js (syntax, lossless):
// the page and the node benches share it. The game stays the only judge (RS_Persona.parsePlaces).
//
// place = {section, id, label, kind: 'point' | 'zone', at: {x, y, z}, area: {x1, y1, x2, y2}, z} (values as text)

import * as sheet from './sheet.js';
import { formatAt, parseAt, parseList } from './values.js';
import { labelOf, slug } from './voice.js';

const KIND = 'place';
export const POINT = 'point';
export const ZONE = 'zone';
export const PLACE_KINDS = [POINT, ZONE];
// Ids the reader keeps for the drawn objectives (target=near, far, very_far): never the id of a place.
const RESERVED = ['near', 'far', 'very_far'];
const AREA_KEYS = ['x1', 'y1', 'x2', 'y2'];
const encoder = new TextEncoder();

// --- the file -------------------------------------------------------------------------------------------------------
export function parsePlaces(text) {
  return sheet.parse(text);
}

export const serialize = (model) => sheet.serialize(model);

// An empty places file: its head only (the game needs format=).
export function newPlacesFile(format = '1') {
  const model = sheet.parse('');
  model.tail = [];
  sheet.setValue(model.head, 'format', format);
  return model;
}

function parseArea(text) {
  const parts = String(text ?? '').split(',').map((v) => v.trim());
  return { area: Object.fromEntries(AREA_KEYS.map((k, i) => [k, parts[i] ?? ''])), z: parts[4] ?? '' };
}

const whole = (v) => /^-?\d+$/.test(String(v ?? '').trim());

// Corners in any order -> lowest corner first (the reader does the same); a missing number stays as typed.
function normalArea(area) {
  const [x1, y1, x2, y2] = AREA_KEYS.map((k) => String(area?.[k] ?? '').trim());
  if (![x1, y1, x2, y2].every(whole)) return { x1, y1, x2, y2 };
  const [ax, bx] = [Number(x1), Number(x2)].sort((a, b) => a - b);
  const [ay, by] = [Number(y1), Number(y2)].sort((a, b) => a - b);
  return { x1: String(ax), y1: String(ay), x2: String(bx), y2: String(by) };
}

function placeOf(section) {
  const areaText = sheet.value(section, 'area');
  const zone = areaText !== null;
  const at = parseAt(sheet.value(section, 'at'));
  const { area, z } = zone ? parseArea(areaText) : { area: Object.fromEntries(AREA_KEYS.map((k) => [k, ''])), z: at.z };
  return { section, id: section.id, label: sheet.value(section, 'label') ?? '', kind: zone ? ZONE : POINT, at, area, z };
}

export function list(model) {
  return sheet.sectionsOf(model, KIND).map(placeOf);
}

export function find(model, id) {
  const section = sheet.section(model, KIND, id);
  return section ? placeOf(section) : null;
}

function uniqueId(model, base) {
  const taken = new Set([...sheet.sectionsOf(model, KIND).map((s) => s.id), ...RESERVED]);
  if (!taken.has(base)) return base;
  for (let n = 2; ; n += 1) if (!taken.has(`${base}_${n}`)) return `${base}_${n}`;
}

// A new place, its id made from its name (charter: never typed), unique and never a distance.
export function addPlace(model, values = {}) {
  const created = sheet.addSection(model, KIND, uniqueId(model, slug(values.label, 'place', 32)));
  setPlace(created, { label: values.label ?? '', ...values });
  return created;
}

// Changes what is given: label; kind with its square (point: at, zone: area + z); the other square removed.
export function setPlace(section, { label, kind, at, area, z }) {
  if (label !== undefined) sheet.setValue(section, 'label', label);
  const current = placeOf(section);
  const next = kind ?? current.kind;
  if (next === ZONE) {
    const corners = normalArea(area ?? current.area);
    const floor = String(z ?? current.z ?? '').trim() || '0';
    sheet.setValue(section, 'at', null);
    sheet.setValue(section, 'area', [...AREA_KEYS.map((k) => corners[k]), floor].join(','));
  } else if (at !== undefined || kind === POINT) {
    const square = at ?? { ...current.at, z: z ?? current.z };
    sheet.setValue(section, 'area', null);
    sheet.setValue(section, 'at', formatAt(square));
  }
}

export function removePlace(model, id) {
  const section = sheet.section(model, KIND, id);
  if (section) sheet.removeSection(model, section);
}

// Centre square of a zone (where a map mark of it goes, D05), or its own square for a point.
export function centre(place) {
  if (place.kind !== ZONE) return place.at;
  const half = (a, b) => String(Math.round((Number(a) + Number(b)) / 2));
  return { x: half(place.area.x1, place.area.x2), y: half(place.area.y1, place.area.y2), z: place.z };
}

// --- light checks of a place (message keys; the game stays the judge) ----------------------------------------------
export function problems(place, catalog) {
  const grammar = catalog.placeGrammar();
  const out = [];
  if (!place.label.trim()) out.push('places.check.no_name');
  if (place.kind === ZONE) {
    const { x1, y1, x2, y2 } = place.area;
    if (![x1, y1, x2, y2].every(whole)) out.push('places.check.no_square');
    else if (Math.abs(x2 - x1) + 1 > grammar.maxAreaSide || Math.abs(y2 - y1) + 1 > grammar.maxAreaSide) {
      out.push('places.check.zone_too_big');
    }
  } else if (!(whole(place.at.x) && whole(place.at.y))) out.push('places.check.no_square');
  if (encoder.encode(place.label).length > grammar.maxLabelBytes) out.push('places.check.name_too_long');
  return out;
}

// --- where a voice names a place (D04) ------------------------------------------------------------------------------
// Keys of a voice that name shared places: block of the sheet, key, whether only points are allowed there (D05). The
// mission parameters of kind place / places (route points) are read from the catalogue, always points.
export const PLACE_REFS = [
  { block: 'head', key: 'marks', points: false },
  { block: 'mission', key: 'target', points: false },
  { block: 'mission', key: 'drops', points: true },
  { block: 'trade', key: 'landing', points: true },
  { block: 'rewards', key: 'cache_place', points: true },
];
const PLACE_PARAM_KINDS = ['place', 'places'];

const blocksOf = (model, block) => (block === 'head' ? [model.head] : sheet.sectionsOf(model, block));

// Every place named by a voice: [{id, block, sectionId, key, points}], in the order of PLACE_REFS then of the
// mission parameters; a distance (near, far, very_far) is no place.
export function references(model, catalog) {
  const distances = new Set(catalog.distances());
  const out = [];
  const push = (block, key, points, owner) => {
    for (const id of sheet.values(owner, key).flatMap(parseList)) {
      if (!distances.has(id)) out.push({ id, block, sectionId: owner.id ?? null, key, points });
    }
  };
  for (const ref of PLACE_REFS) for (const owner of blocksOf(model, ref.block)) push(ref.block, ref.key, ref.points, owner);
  for (const mission of sheet.sectionsOf(model, 'mission')) {
    const type = catalog.missionType(sheet.value(mission, 'type'));
    for (const [key, kind] of Object.entries(type?.params ?? {})) {
      if (PLACE_PARAM_KINDS.includes(kind)) push('mission', key, true, mission);
    }
  }
  return out;
}

// Voices [{id, name, model}] that name place `id`.
export function usedBy(id, voices, catalog) {
  return voices.filter((v) => references(v.model, catalog).some((r) => r.id === id));
}

// Options of a list of places: [{value, label, kind}], the points only when `points` (D05); never a square or an id
// on screen (a place without a name shows its id in words).
export function choices(model, { points = false } = {}) {
  return list(model).filter((p) => !points || p.kind === POINT)
    .map((p) => ({ value: p.id, label: p.label || labelOf(p.id), kind: p.kind }));
}
