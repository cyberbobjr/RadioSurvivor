// Recipe help of a voice (E27-T02, ADR recettes-radio D02 to D04, D06): the [help] section of her sheet, read and
// written as {jobs, from, delay}. Pure module, no DOM: the form (recipehelpform.js) and the node benches share it.
// The jobs, levels and delays offered and the value of an absent from= / delay= are the catalogue's grammar of [help]
// (RS_Persona.lua). No job ticked = no [help] section: the voice never helps with recipes.

import * as sheet from './sheet.js';
import { formatList, parseList } from './values.js';

export const KIND = 'help';
// Keys of [help] beside jobs=, written only when they differ from the reader's default.
const SETTINGS = ['from', 'delay'];

// {jobs: [...], from, delay} of the sheet (`grammar`: catalog.section('help')).
export function readHelp(model, grammar) {
  const section = sheet.section(model, KIND);
  const defaults = grammar?.defaults ?? {};
  const help = { jobs: section ? parseList(sheet.value(section, 'jobs')) : [] };
  for (const key of SETTINGS) help[key] = (section && sheet.value(section, key)) ?? defaults[key] ?? null;
  return help;
}

// Writes `help` into the sheet: the section added after the others when a job is ticked, removed when none is; its
// other lines (comments, unknown keys) kept.
export function writeHelp(model, help, grammar) {
  const current = sheet.section(model, KIND);
  if (!help.jobs.length) {
    if (current) sheet.removeSection(model, current);
    return;
  }
  const section = current ?? sheet.addSection(model, KIND);
  const defaults = grammar?.defaults ?? {};
  sheet.setValue(section, 'jobs', formatList(help.jobs));
  for (const key of SETTINGS) sheet.setValue(section, key, help[key] === defaults[key] ? null : help[key]);
}
