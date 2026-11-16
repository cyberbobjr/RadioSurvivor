// Form of a whole section generated from its grammar in the catalogue (catalog.sections[kind]: keys, required,
// repeatable, closed choices): used by the advanced panels ([trade], [note], own [category]). A key added to a section
// of the mod appears here after the catalogue is regenerated. `forms` (stock.js SECTION_FORMS):
// - editors {kind: {key: entry}} gives a key a form of its own instead of the plain field or list of lines: an entry is
//   either a function (ctx, section, key) => control, or advanced(form): the key is shown only when the sheet already
//   uses it, in a closed "advanced settings" panel at the end of the form (a key a new voice never needs), with that
//   form, or its plain field for ADVANCED;
// - groups {kind: [{title, keys}]}: the questions of the form, in order, each under its title (E24-T02); the keys of no
//   group come after them in the grammar's order.
// A required key is marked with one star, said once at the top of the form (charter rule 4); a closed choice is a set
// of cards (charter rule 7), with the icon i18n choice.<key>.<value>.icon when there is one.

import { h } from './dom.js';
import { hint } from './help.js';
import * as sheet from './sheet.js';
import { cards, fold, listEditor, row, textInput } from './widgets.js';

export const advanced = (form = null) => Object.freeze({ advanced: true, form });
export const ADVANCED = advanced();

// [{title, keys}] covering every key of the grammar once.
function groupsOf(keys, groups = []) {
  const listed = groups.flatMap((g) => g.keys);
  const rest = keys.filter((k) => !listed.includes(k));
  const out = groups.map((g) => ({ title: g.title, keys: g.keys.filter((k) => keys.includes(k)) }));
  return rest.length ? [...out, { title: null, keys: rest }] : out;
}

export function sectionForm(ctx, section, grammar, { editors = {}, groups = {} } = {}) {
  const { t, changed } = ctx;
  const label = (key) => `${t(`key.${grammar.kind}.${key}`, {}, key)}${grammar.required.includes(key) ? ' *' : ''}`;
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
      const options = choices.map((c) => ({ value: c, label: t(`choice.${key}.${c}`, {}, c),
        help: t(`help.${grammar.kind}.${key}.${c}.what`, {}, '') || null, icon: t(`choice.${key}.${c}.icon`, {}, '') || null }));
      return row(label(key), (id) => cards(`${grammar.kind}-${key}`, options, sheet.value(section, key) ?? '',
        (v) => { sheet.setValue(section, key, v); changed(); }, { id }), help(key), keyHint(key, options));
    }
    return row(label(key), (id) => textInput(id, sheet.value(section, key), (v) => {
      sheet.setValue(section, key, v);
      changed();
    }, { spellcheck: 'false', placeholder: t(`key.${grammar.kind}.${key}.placeholder`, {}, '') }), help(key), keyHint(key));
  };

  const formRow = (key, form) => row(label(key), () => form(ctx, section, key), help(key), keyHint(key));

  const main = [];
  const more = [];
  for (const group of groupsOf(grammar.keys, groups[grammar.kind])) {
    const rows = [];
    for (const key of group.keys) {
      const editor = editors[grammar.kind]?.[key];
      if (editor?.advanced) {
        if (sheet.values(section, key).length) more.push(editor.form ? formRow(key, editor.form) : plainRow(key));
      } else rows.push(editor ? formRow(key, editor) : plainRow(key));
    }
    if (rows.length) main.push(group.title ? h('section', { class: 'question' }, h('h4', { text: t(group.title) }), rows) : rows);
  }
  if (grammar.required.length) main.unshift(h('p', { class: 'help legend', text: t('field.required_legend') }));
  if (more.length) {
    main.push(fold(t('section.advanced'), false, h('p', { class: 'help', text: t('section.advanced_help') }), more));
  }
  return main;
}
