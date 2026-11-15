// Form of a whole section generated from its grammar in the catalogue (catalog.sections[kind]: keys, required,
// repeatable, closed choices): used by the advanced panels ([trade], [note], own [category]). A key added to a section
// of the mod appears here after the catalogue is regenerated. `forms` (stock.js SECTION_FORMS):
// - editors {kind: {key: entry}} gives a key a form of its own instead of the plain field or list of lines: an entry is
//   either a function (ctx, section, key) => control, or ADVANCED: the key keeps its plain field but is shown only when
//   the sheet already uses it, in a closed "advanced settings" panel at the end of the form (a key a new voice never
//   needs);
// - order {kind: [key, ...]} shows these keys first, in that order (the order a player fills them), the other keys
//   after them in the grammar's order.

import { h, select } from './dom.js';
import { hint, selectHelp } from './help.js';
import * as sheet from './sheet.js';
import { fold, listEditor, row, textInput } from './widgets.js';

export const ADVANCED = Object.freeze({ advanced: true });

function ordered(keys, first = []) {
  return [...first.filter((k) => keys.includes(k)), ...keys.filter((k) => !first.includes(k))];
}

export function sectionForm(ctx, section, grammar, { editors = {}, order = {} } = {}) {
  const { t, changed } = ctx;
  const label = (key) => `${t(`key.${grammar.kind}.${key}`, {}, key)}${grammar.required.includes(key) ? ` ${t('field.required')}` : ''}`;
  const help = (key) => t(`key.${grammar.kind}.${key}.help`, {}, '') || null;
  // "?" of a key: help.<kind>.<key>, its closed choices help.<kind>.<key>.<value> (help.js).
  const topic = (key) => `help.${grammar.kind}.${key}`;
  const keyHint = (key, options = []) => hint(t, topic(key), { label: t(`key.${grammar.kind}.${key}`, {}, key),
    choices: options.map((o) => ({ label: o.label, topic: `${topic(key)}.${o.value}` })) });

  const plainRow = (key) => {
    if (grammar.repeatable.includes(key)) {
      return row(label(key), () => listEditor(t, sheet.values(section, key), (list) => {
        sheet.setValues(section, key, list);
        changed();
      }, t(`key.${grammar.kind}.${key}.placeholder`, {}, '')), help(key), keyHint(key));
    }
    const choices = grammar.choices[key];
    if (choices) {
      const options = choices.map((c) => ({ value: c, label: t(`choice.${key}.${c}`, {}, c) }));
      return row(label(key), (id) => {
        const field = select([{ value: '', label: t('field.choose') }, ...options], sheet.value(section, key) ?? '',
          (v) => { sheet.setValue(section, key, v); changed(); }, { id });
        return h('div', { class: 'stack' }, field, selectHelp(t, topic(key), field));
      }, help(key), keyHint(key, options));
    }
    return row(label(key), (id) => textInput(id, sheet.value(section, key), (v) => {
      sheet.setValue(section, key, v);
      changed();
    }, { spellcheck: 'false', placeholder: t(`key.${grammar.kind}.${key}.placeholder`, {}, '') }), help(key), keyHint(key));
  };

  const main = [];
  const advanced = [];
  for (const key of ordered(grammar.keys, order[grammar.kind])) {
    const editor = editors[grammar.kind]?.[key];
    if (editor === ADVANCED) {
      if (sheet.values(section, key).length) advanced.push(plainRow(key));
    } else if (editor) {
      main.push(row(label(key), () => editor(ctx, section, key), help(key), keyHint(key)));
    } else {
      main.push(plainRow(key));
    }
  }
  if (advanced.length) {
    main.push(fold(t('section.advanced'), false, h('p', { class: 'help', text: t('section.advanced_help') }), advanced));
  }
  return main;
}
