// Form fields by parameter kind (catalog.paramKinds): one widget per kind, all reading and writing the raw text of the
// sheet value. A kind the page does not know yet gets a plain text field: a new kind in the mod never breaks the page.
//
// field(kind, ctx) ; ctx = {t, id, value, onChange(text), rerender(), places: [{value, label}],
//                           categories: [{value, label}], skills: [{value, label}], items: item index (items.js)}

import { categoryIds } from './categories.js';
import { h, select } from './dom.js';
import { selectHelp } from './help.js';
import { parseList } from './values.js';
import { itemChoice } from './itempicker.js';
import * as voice from './voice.js';
import { button, rangeStepper, removeButton, stepper } from './widgets.js';

const none = (t) => ({ value: '', label: t('field.choose') });

// A select and, under it, the help line of its selected value (help.js).
const withChoiceHelp = (t, prefix, field) => h('div', { class: 'stack' }, field, selectHelp(t, prefix, field));

export const FIELDS = {
  count: ({ t, id, value, onChange, label }) => stepper(value, onChange, { id, min: 0, label: label ?? t('kind.count') }),

  range: ({ t, id, value, onChange }) => rangeStepper(t, value, onChange, { id }),

  category: ({ t, id, value, onChange, categories }) => withChoiceHelp(t, 'help.shared_category',
    select([none(t), ...categories], value, onChange, { id })),
  place: ({ t, id, value, onChange, places }) => select([none(t), ...places], value, onChange, { id }),
  skill: ({ t, id, value, onChange, skills }) => withChoiceHelp(t, 'help.skill',
    select([none(t), ...skills], value, onChange, { id })),

  // Ordered places (route): one picker per stop, add, move up, remove.
  places: ({ t, id, value, onChange, places, rerender }) => {
    const list = parseList(value);
    const write = () => { onChange(list.filter((p) => p).join(',')); rerender(); };
    return h('div', { class: 'stack', id },
      list.map((place, index) => h('div', { class: 'inline' },
        h('span', { class: 'stop', text: String(index + 1) }),
        select([none(t), ...places], place, (v) => { list[index] = v; write(); }, { 'aria-label': t('field.stop', { n: index + 1 }) }),
        index > 0 && button('icon', { title: t('field.up'), 'aria-label': t('field.up'),
          onClick: () => { [list[index - 1], list[index]] = [list[index], list[index - 1]]; write(); } }, '↑'),
        removeButton(t, () => { list.splice(index, 1); write(); }))),
      button('add', { onClick: () => { list.push(places[0]?.value ?? ''); write(); } },
        t('field.add_stop')));
  },

  // An item picked in the item browser, shown by its name; the sheet stores Module.Type (itempicker.js).
  item: ({ t, id, value, onChange, items }) => itemChoice(t, items, value, onChange, { id }),

  text: ({ id, value, onChange }) => h('input', { id, type: 'text', value, onInput: (e) => onChange(e.target.value) }),
};

export function field(kind, ctx) {
  return (FIELDS[kind] ?? FIELDS.text)(ctx);
}

// Choices the fields offer for one voice: its places (all, and dead drops), the shared and own categories, skills.
// `byKind` gives the choices of a parameter kind (first one = default of a new reward or stop).
export function fieldOptions(model, catalog, t) {
  const places = voice.places(model);
  const label = (p) => p.label || voice.labelOf(p.id);   // never its coordinates (E24-T02)
  const opts = {
    places: places.map((p) => ({ value: p.id, label: label(p) })),
    drops: places.filter((p) => p.uses.includes('drop')).map((p) => ({ value: p.id, label: label(p) })),
    categories: categoryIds(model, catalog).map((c) => ({ value: c, label: t(`category.${c}`, {}, voice.labelOf(c)) })),
    skills: catalog.skills().map((s) => ({ value: s, label: t(`skill.${s}`, {}, s) })),
    items: catalog.itemIndex(),
  };
  opts.byKind = { place: opts.places, places: opts.places, category: opts.categories, skill: opts.skills };
  return opts;
}
