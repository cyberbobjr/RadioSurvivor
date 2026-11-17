// Form fields by parameter kind (catalog.paramKinds): one widget per kind, all reading and writing the raw text of the
// sheet value. A kind the page does not know yet gets a plain text field: a new kind in the mod never breaks the page.
//
// field(kind, ctx) ; ctx = {t, id, value, onChange(text), rerender(), step: the step's context (shared places of
//                           placeform.js lists), categories: [{value, label}], skills: [{value, label}],
//                           items: item index (items.js)}

import { categoryIds } from './categories.js';
import { h, select } from './dom.js';
import { selectHelp } from './help.js';
import { placeSelect } from './placeform.js';
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
  // A shared place where the player needs an exact spot (D05): points only, "New place…" at the end.
  place: ({ t, id, value, onChange, rerender, step }) => placeSelect(step, value, (v) => { onChange(v); rerender(); },
    { points: true, empty: t('field.choose'), id }),
  skill: ({ t, id, value, onChange, skills }) => withChoiceHelp(t, 'help.skill',
    select([none(t), ...skills], value, onChange, { id })),

  // Ordered shared points (route): one list per stop, add, move up, remove.
  places: ({ t, id, value, onChange, rerender, step }) => {
    const list = parseList(value);
    const write = () => { onChange(list.filter((p) => p).join(',')); rerender(); };
    const points = step.places.choices({ points: true });
    return h('div', { class: 'stack', id },
      list.map((place, index) => h('div', { class: 'inline' },
        h('span', { class: 'stop', text: String(index + 1), 'aria-label': t('field.stop', { n: index + 1 }) }),
        placeSelect(step, place, (v) => { list[index] = v; write(); }, { points: true, empty: t('field.choose') }),
        index > 0 && button('icon', { title: t('field.up'), 'aria-label': t('field.up'),
          onClick: () => { [list[index - 1], list[index]] = [list[index], list[index - 1]]; write(); } }, '↑'),
        removeButton(t, () => { list.splice(index, 1); write(); }))),
      button('add', { onClick: () => { list.push(points[0]?.value ?? ''); write(); } },
        t('field.add_stop')));
  },

  // An item picked in the item browser, shown by its name; the sheet stores Module.Type (itempicker.js).
  item: ({ t, id, value, onChange, items }) => itemChoice(t, items, value, onChange, { id }),

  text: ({ id, value, onChange }) => h('input', { id, type: 'text', value, onInput: (e) => onChange(e.target.value) }),
};

export function field(kind, ctx) {
  return (FIELDS[kind] ?? FIELDS.text)(ctx);
}

// Choices the fields offer for one voice (step context `step`): the shared places (through the step's place store),
// the shared and own categories, skills. `byKind` gives the choices of a parameter kind (first one = default of a new
// reward or stop).
export function fieldOptions(step, t) {
  const { model, catalog } = step;
  const opts = {
    step,
    categories: categoryIds(model, catalog).map((c) => ({ value: c, label: t(`category.${c}`, {}, voice.labelOf(c)) })),
    skills: catalog.skills().map((s) => ({ value: s, label: t(`skill.${s}`, {}, s) })),
    items: catalog.itemIndex(),
  };
  const points = step.places.choices({ points: true });
  opts.byKind = { place: points, places: points, category: opts.categories, skill: opts.skills };
  return opts;
}
