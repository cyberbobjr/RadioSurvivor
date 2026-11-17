// "Recipe help" block of the voice form (E27-T02, charter rules 4 and 7): the jobs she knows as boxes in plain words,
// then, once a job is ticked, from which reputation she helps and when she answers, as cards. Reads and writes [help]
// through recipehelp.js; every choice comes from the catalogue's grammar of [help], its words from i18n:
// recipehelp.<key>.<value> (+ .help, .icon), the "?" topics help.help.<key>(.<value>).

import { h } from './dom.js';
import { hint } from './help.js';
import { KIND, readHelp, writeHelp } from './recipehelp.js';
import { cards, checkboxes, row } from './widgets.js';

// Keys of [help] chosen as cards once a job is ticked, in the order of the questions.
const CARD_KEYS = ['from', 'delay'];

function option(t, key, value) {
  return { value, label: t(`recipehelp.${key}.${value}`, {}, value),
    help: t(`recipehelp.${key}.${value}.help`, {}, '') || null, icon: t(`recipehelp.${key}.${value}.icon`, {}, '') || null };
}

function keyHint(t, key, options = []) {
  return hint(t, `help.${KIND}.${key}`, { label: t(`recipehelp.${key}`),
    choices: options.map((o) => ({ label: o.label, topic: `help.${KIND}.${key}.${o.value}` })) });
}

export function recipeHelpBlock(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  const grammar = catalog.section(KIND);
  if (!grammar) return null;
  const help = readHelp(model, grammar);
  const write = () => { writeHelp(model, help, grammar); changed(); };
  // Jobs in the alphabetical order of their words in the page language.
  const jobs = (grammar.choices.jobs ?? []).map((v) => option(t, 'jobs', v))
    .sort((a, b) => a.label.localeCompare(b.label));
  const cardRow = (key) => {
    const options = (grammar.choices[key] ?? []).map((v) => option(t, key, v));
    return row(t(`recipehelp.${key}`), (id) => cards(`help-${key}`, options, help[key], (v) => {
      help[key] = v;
      write();
    }, { id, class: 'compact' }), t(`recipehelp.${key}_help`), keyHint(t, key, options));
  };
  return h('section', { class: 'question recipe-help' },
    h('h4', { text: t('recipehelp.title') }),
    row(t('recipehelp.jobs'), () => checkboxes(jobs, help.jobs, (list) => {
      help.jobs = list;
      write();
      rerender();
    }, { class: 'checks cols' }), t('recipehelp.jobs_help'), keyHint(t, 'jobs')),
    help.jobs.length > 0 && CARD_KEYS.map(cardRow));
}
