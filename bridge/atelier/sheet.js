// Voice sheet, format 1 (docs/specifications-techniques/persona-format.md): syntax only, never the game's rules (ADR
// atelier-voix D03). Pure module, no DOM: the page and the node benches share it.
//
// parse(text) -> model, serialize(model) -> text, lossless: unknown keys, their order, blank lines and comments are
// kept. Every blank or comment line belongs to the line that follows it (`before` of an entry, a section or [prompt]);
// the ones left at the end of a file without [prompt] are the `tail` of the model.
//
// model = { head: {entries}, sections: [{kind, id, header, before, entries}], prompt: {before, header, text} | null,
//           tail: [lines] }
// entry = { key, value, raw, before }   (key null: a line that is not key=value, kept as raw)
// A changed entry or section header is written back as `key=value` / `[kind id]`; an untouched one as its raw line.

const SECTION_RE = /^\s*\[\s*([^\]\s]+)(?:\s+([^\]\s]+))?\s*\]\s*$/;
const PROMPT = 'prompt';

function isBlankOrComment(line) {
  const trimmed = line.trim();
  return trimmed === '' || trimmed.startsWith('#');
}

function splitKeyValue(line) {
  const at = line.indexOf('=');
  if (at < 0) return null;
  return { key: line.slice(0, at).trim(), value: line.slice(at + 1).trim() };
}

function sectionHeader(line) {
  if (!line.trim().startsWith('[')) return null;
  const match = SECTION_RE.exec(line);
  return match ? { kind: match[1], id: match[2] ?? null } : { kind: null, id: null };
}

function entryOf(line, before) {
  const kv = splitKeyValue(line);
  return { key: kv ? kv.key : null, value: kv ? kv.value : null, raw: line, before };
}

export function normalizeText(text) {
  let out = String(text ?? '');
  if (out.startsWith('﻿')) out = out.slice(1);
  return out.replace(/\r\n?/g, '\n');
}

export function parse(text) {
  const lines = normalizeText(text).split('\n');
  const model = { head: { entries: [] }, sections: [], prompt: null, tail: [] };
  let block = model.head;
  let pending = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (isBlankOrComment(line)) {
      pending.push(line);
      continue;
    }
    const header = sectionHeader(line);
    if (header && header.kind === PROMPT && header.id === null) {
      const rest = index + 1 < lines.length ? lines.slice(index + 1).join('\n') : null;
      model.prompt = { before: pending, header: line, text: rest };
      return model;
    }
    if (header) {
      block = { kind: header.kind, id: header.id, header: line, before: pending, entries: [] };
      model.sections.push(block);
    } else {
      block.entries.push(entryOf(line, pending));
    }
    pending = [];
  }
  model.tail = pending;
  return model;
}

// Where line `lineNumber` (from 1, as the game counts them) of a sheet text is, in the shape of the checks' `where`
// (E22-T04): {block: 'head' | <section kind> | 'prompt', id, field: key of a key=value line, else null}. A blank or
// comment line belongs to the block it stands in; a number beyond the end points at the last line.
export function locate(text, lineNumber) {
  const lines = normalizeText(text).split('\n');
  const target = Math.min(Math.max(1, Number(lineNumber) || 1), lines.length) - 1;
  let where = { block: 'head', id: null, field: null };
  for (let index = 0; index <= target; index += 1) {
    const line = lines[index];
    if (isBlankOrComment(line)) { where = { ...where, field: null }; continue; }
    const header = sectionHeader(line);
    if (header && header.kind === PROMPT && header.id === null) return { block: 'prompt', id: null, field: null };
    where = header ? { block: header.kind, id: header.id, field: null }
      : { ...where, field: splitKeyValue(line)?.key ?? null };
  }
  return where;
}

function entryLine(entry) {
  if (entry.key === null) return entry.raw;
  const kv = entry.raw === null ? null : splitKeyValue(entry.raw);
  if (kv && kv.key === entry.key && kv.value === entry.value) return entry.raw;
  return `${entry.key}=${entry.value}`;
}

function headerLine(section) {
  const parsed = section.header === null ? null : sectionHeader(section.header);
  if (parsed && parsed.kind === section.kind && parsed.id === section.id) return section.header;
  return section.id === null ? `[${section.kind}]` : `[${section.kind} ${section.id}]`;
}

export function serialize(model) {
  const out = [];
  const pushEntries = (entries) => entries.forEach((e) => out.push(...e.before, entryLine(e)));
  pushEntries(model.head.entries);
  for (const section of model.sections) {
    out.push(...section.before, headerLine(section));
    pushEntries(section.entries);
  }
  if (!model.prompt) return [...out, ...model.tail].join('\n');
  out.push(...model.prompt.before, model.prompt.header ?? '[prompt]');
  const head = out.join('\n');
  return model.prompt.text === null ? head : `${head}\n${model.prompt.text}`;
}

// --- entries of a block (the head or a section) ---------------------------------------------------------------------
export function value(block, key) {
  const entry = block.entries.find((e) => e.key === key);
  return entry ? entry.value : null;
}

export function values(block, key) {
  return block.entries.filter((e) => e.key === key).map((e) => e.value);
}

export function keys(block) {
  return block.entries.filter((e) => e.key !== null).map((e) => e.key);
}

// One value: changed in place, appended when missing, removed when empty (the format refuses empty values).
export function setValue(block, key, newValue) {
  setValues(block, key, newValue === null || newValue === undefined || String(newValue).trim() === ''
    ? [] : [String(newValue).trim()]);
}

// Repeated key (knows=, item=...): values changed in place, extra lines removed, new ones after the last one.
export function setValues(block, key, newValues) {
  const wanted = newValues.map((v) => String(v).trim()).filter((v) => v !== '');
  const existing = block.entries.filter((e) => e.key === key);
  existing.forEach((entry, index) => {
    if (index < wanted.length) entry.value = wanted[index];
  });
  if (wanted.length < existing.length) {
    const removed = new Set(existing.slice(wanted.length));
    block.entries = block.entries.filter((e) => !removed.has(e));
    return;
  }
  const last = existing[existing.length - 1];
  const at = last ? block.entries.indexOf(last) + 1 : block.entries.length;
  const added = wanted.slice(existing.length).map((v) => ({ key, value: v, raw: null, before: [] }));
  block.entries.splice(at, 0, ...added);
}

// --- sections -------------------------------------------------------------------------------------------------------
export function sectionsOf(model, kind) {
  return model.sections.filter((s) => s.kind === kind);
}

export function section(model, kind, id = null) {
  return model.sections.find((s) => s.kind === kind && s.id === id) ?? null;
}

// New section after the last one of its kind (file order kept), else after every section.
export function addSection(model, kind, id = null) {
  const created = { kind, id, header: null, before: [''], entries: [] };
  const last = sectionsOf(model, kind).pop();
  const at = last ? model.sections.indexOf(last) + 1 : model.sections.length;
  model.sections.splice(at, 0, created);
  return created;
}

export function removeSection(model, removed) {
  model.sections = model.sections.filter((s) => s !== removed);
}

// --- prompt and description -----------------------------------------------------------------------------------------
export function promptText(model) {
  return model.prompt && model.prompt.text !== null ? model.prompt.text.replace(/\s+$/, '') : '';
}

export function setPromptText(model, text) {
  const body = `${String(text ?? '').replace(/\s+$/, '')}\n`;
  if (model.prompt) {
    model.prompt.text = body;
    return;
  }
  const comments = model.tail.filter((line) => line.trim() !== '');
  model.prompt = { before: ['', ...comments], header: '[prompt]', text: body };
  model.tail = [];
}

// First block of the file: its leading comment lines are the voice's short description (the game skips them).
function firstBefore(model) {
  if (model.head.entries.length) return model.head.entries[0];
  return model.sections[0] ?? model.prompt;
}

export function description(model) {
  const holder = firstBefore(model);
  if (!holder) return '';
  const lines = [];
  for (const line of holder.before) {
    if (!line.trim().startsWith('#')) break;
    lines.push(line.trim().replace(/^#\s?/, ''));
  }
  return lines.join('\n');
}

export function setDescription(model, text) {
  const holder = firstBefore(model);
  if (!holder) return;
  let count = 0;
  while (count < holder.before.length && holder.before[count].trim().startsWith('#')) count += 1;
  const lines = String(text ?? '').split('\n').map((l) => l.trimEnd()).filter((l) => l.trim() !== '');
  holder.before.splice(0, count, ...lines.map((l) => `# ${l}`));
}
