// Value syntaxes of a voice sheet read and written by the workshop (frequencies, hours, lists, coordinates, ranges,
// reward pool). Pure module: text <-> plain data, no rule of the game beyond the shape of a value (ADR D03).

const MHZ_RE = /^\d{1,4}(?:\.\d)?$/;
// Frequency of a sheet (frequency=, RS_Persona.lua): MHz with exactly one decimal.
const SHEET_MHZ_RE = /^\d{1,4}\.\d$/;
const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

export function parseList(text) {
  return String(text ?? '').split(',').map((v) => v.trim()).filter((v) => v !== '');
}

export function formatList(items) {
  return items.filter((v) => String(v).trim() !== '').join(',');
}

// --- frequencies ----------------------------------------------------------------------------------------------------
export function mhzToKhz(text) {
  const trimmed = String(text ?? '').trim();
  return MHZ_RE.test(trimmed) ? Math.round(Number(trimmed) * 1000) : null;
}

export function khzToMhz(khz) {
  return (khz / 1000).toFixed(1);
}

// Frequency written in a sheet (frequency=): kHz, or null unless it is MHz with one decimal (145.0) as the game reads it.
export function sheetFrequency(text) {
  const trimmed = String(text ?? '').trim();
  return SHEET_MHZ_RE.test(trimmed) ? Math.round(Number(trimmed) * 1000) : null;
}

// --- listening hours ------------------------------------------------------------------------------------------------
export function isTime(text) {
  return TIME_RE.test(String(text ?? '').trim());
}

// "07:00-10:00,16:00-19:00" -> [["07:00", "10:00"], ["16:00", "19:00"]] ; "always" or nothing -> [].
export function parseHours(text) {
  const trimmed = String(text ?? '').trim();
  if (trimmed === '' || trimmed === 'always') return [];
  return parseList(trimmed).map((part) => {
    const [from, to] = part.split('-').map((v) => (v ?? '').trim());
    return [from ?? '', to ?? ''];
  });
}

export function formatHours(ranges) {
  const kept = ranges.filter(([from, to]) => from && to);
  return kept.length ? kept.map(([from, to]) => `${from}-${to}`).join(',') : 'always';
}

// --- coordinates and ranges -----------------------------------------------------------------------------------------
export function parseAt(text) {
  const parts = String(text ?? '').split(',').map((v) => v.trim());
  const [x, y, z] = parts;
  return { x: x ?? '', y: y ?? '', z: z ?? '' };
}

export function formatAt({ x, y, z }) {
  return [x, y, z === '' || z === undefined ? '0' : z].map((v) => String(v).trim()).join(',');
}

// A map position as copied on the community map ("7966, 11751", "7966, 11751, 1", "x: 7966 y: 11751"): two or three
// whole numbers, separated by commas, semicolons or spaces, words around them ignored -> {x, y, z?} as text; anything
// else (one number, a decimal, more than three numbers) -> null, so a plain paste of one number stays a plain paste.
export function parseSquare(text) {
  const numbers = String(text ?? '').match(/\d+(?:\.\d+)?/g) ?? [];
  if (numbers.length < 2 || numbers.length > 3 || numbers.some((n) => n.includes('.'))) return null;
  const [x, y, z] = numbers;
  return z === undefined ? { x, y } : { x, y, z };
}

export function isInteger(text) {
  return /^-?\d+$/.test(String(text ?? '').trim());
}

// "2-4" -> {min: "2", max: "4"} ; "3" -> {min: "3", max: "3"}.
export function parseRange(text) {
  const [min, max] = String(text ?? '').split('-').map((v) => v.trim());
  return { min: min ?? '', max: max ?? min ?? '' };
}

export function formatRange({ min, max }) {
  const lo = String(min ?? '').trim();
  const hi = String(max ?? '').trim();
  return hi === '' || hi === lo ? lo : `${lo}-${hi}`;
}

// --- reward pool ----------------------------------------------------------------------------------------------------
// "cache:medical:1, frequency:1" -> [{kind: "cache", param: "medical", weight: "1"}, {kind: "frequency", ...}]
export function parsePool(text) {
  return parseList(text).map((part) => {
    const bits = part.split(':').map((v) => v.trim());
    if (bits.length >= 3) return { kind: bits[0], param: bits.slice(1, -1).join(':'), weight: bits[bits.length - 1] };
    return { kind: bits[0], param: '', weight: bits[1] ?? '' };
  });
}

export function formatPool(rows) {
  return rows.filter((r) => r.kind)
    .map((r) => [r.kind, r.param, r.weight || '1'].filter((v) => v !== '' && v !== null && v !== undefined).join(':'))
    .join(', ');
}

// --- draw chances (E22-T12, user 2026-11-15): three plain levels instead of a number to type -------------------------
// A weight read from a sheet that is not one of them is kept as is and shown as "custom".
export const CHANCES = [{ level: 'rare', weight: '1' }, { level: 'normal', weight: '2' }, { level: 'often', weight: '4' }];
export const DEFAULT_CHANCE = '2';

// Level of a weight ("rare", "normal", "often"), or null when the weight is not one of the three.
export function chanceLevel(weight) {
  const text = String(weight ?? '').trim();
  return CHANCES.find((c) => Number(c.weight) === Number(text) && text !== '')?.level ?? null;
}

// --- trader stock and loot lists ------------------------------------------------------------------------------------
// "Base.Battery:2-6" -> {type: "Base.Battery", amount: "2-6"} ; the amount is a range or the name of a group= line.
// Anything after the amount (the kg of the former syntax) is dropped: the game reads the weight in the item script.
export function parseStockItem(text) {
  const [type, amount] = String(text ?? '').split(':').map((v) => v.trim());
  return { type: type ?? '', amount: amount ?? '' };
}

export function formatStockItem({ type, amount }) {
  const name = String(type ?? '').trim();
  return name ? [name, String(amount ?? '').trim() || '1'].join(':') : '';
}

// "alcohol:2-5:3" -> "alcohol": name of a group= line of [trade].
export function groupName(text) {
  return String(text ?? '').split(':')[0].trim();
}

// "OfficeDesk:4" -> {list: "OfficeDesk", weight: "4"} (loot= and glovebox= of [note]).
export function parseLootList(text) {
  const raw = String(text ?? '');
  const at = raw.lastIndexOf(':');
  return at < 0 ? { list: raw.trim(), weight: '' } : { list: raw.slice(0, at).trim(), weight: raw.slice(at + 1).trim() };
}

export function formatLootList({ list, weight }) {
  const name = String(list ?? '').trim();
  return name ? `${name}:${String(weight ?? '').trim() || DEFAULT_CHANCE}` : '';
}

// --- lots of the trader's stock (group= of [trade]) -----------------------------------------------------------------
// "seeds:3-8:4" -> {name: "seeds", total: "3-8", kinds: "4"} ; kinds is optional ("at most N different items").
export function parseGroup(text) {
  const [name, total, kinds] = String(text ?? '').split(':').map((v) => v.trim());
  return { name: name ?? '', total: total ?? '', kinds: kinds ?? '' };
}

export function formatGroup({ name, total, kinds }) {
  const id = String(name ?? '').trim();
  if (!id) return '';
  const parts = [id, String(total ?? '').trim() || '1'];
  if (String(kinds ?? '').trim()) parts.push(String(kinds).trim());
  return parts.join(':');
}

// --- trader's margin: "0.10-0.50" <-> percents {min: "10", max: "50"} ; both empty -> no line (the game's default) ----
const percent = (v) => (v === undefined || v.trim() === '' || Number.isNaN(Number(v)) ? '' : String(Math.round(Number(v) * 100)));
const fraction = (v) => (Number(v) / 100).toFixed(2);

export function parseMargin(text) {
  const [min, max] = String(text ?? '').split('-');
  return { min: percent(min), max: percent(max) };
}

export function formatMargin({ min, max }) {
  const lo = String(min ?? '').trim();
  const hi = String(max ?? '').trim();
  return lo === '' || hi === '' ? '' : `${fraction(lo)}-${fraction(hi)}`;
}

// --- one time range "02:00-04:00" (meeting of [trade]) <-> ["02:00", "04:00"] ; incomplete -> no line -------------
export function parseTimeRange(text) {
  return parseHours(text)[0] ?? ['', ''];
}

export function formatTimeRange([from, to]) {
  return from && to ? `${from}-${to}` : '';
}

// --- the voice's frequency in a written text (call=, note text=): %1 in the sheet, a word on screen (E24-T02) --------
export const FREQUENCY_MARK = '%1';
export const freqToScreen = (text, word) => String(text ?? '').split(FREQUENCY_MARK).join(word);
export const freqToSheet = (text, word) => String(text ?? '').split(word).join(FREQUENCY_MARK);

// --- written text of a note line: UTF-8 bytes (the game's limit counts bytes, an accent takes two) -------------------
export function utf8Bytes(text) {
  return new TextEncoder().encode(String(text ?? '')).length;
}
