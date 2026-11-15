// Step 5, rewards: the pool of [rewards] built from the reward kinds of the catalogue (with the field of their
// parameter kind), each with how often it comes out (Rarely / Normally / Often), then the optional advanced panels,
// closed by default: trade ([trade]), frequency note ([note]) and the voice's own categories ([category]), all
// generated from the section grammar, the keys with a form of their own registered in stock.js.

import { h } from '../dom.js';
import { field, fieldOptions } from '../fields.js';
import { hint } from '../help.js';
import { sectionForm } from '../sectionform.js';
import * as sheet from '../sheet.js';
import { SECTION_ACTIONS, SECTION_FORMS } from '../stock.js';
import { DEFAULT_CHANCE } from '../values.js';
import * as voice from '../voice.js';
import { button, chanceChoice, fold, removeButton, row, textInput } from '../widgets.js';

const kindLabel = (t, kind) => t(`reward.${kind}`, {}, kind);
const kindHint = (t, kind) => hint(t, `help.reward.${kind}`, { label: kindLabel(t, kind) });

// "About 1 time in 3", worked out from the weights of the pool.
function oneIn(t, rows, reward) {
  const total = rows.reduce((sum, r) => sum + (Number(r.weight) || 0), 0);
  const weight = Number(reward.weight) || 0;
  if (!total || !weight) return '';
  const n = Math.max(1, Math.round(total / weight));
  return n === 1 ? t('rewards.always') : t('rewards.one_in', { n });
}

function poolEditor(ctx, opts) {
  const { model, catalog, t, changed, rerender } = ctx;
  const rows = voice.pool(model);
  const write = (structural) => { voice.setPool(model, rows); changed(); if (structural) rerender(); };
  const kinds = catalog.rewardKinds();
  return h('div', { class: 'stack' },
    rows.length === 0 && h('p', { class: 'muted', text: t('rewards.none') }),
    rows.map((reward, index) => {
      const kind = catalog.rewardKind(reward.kind);
      return h('article', { class: 'card reward' },
        h('header', { class: 'card-head' },
          h('b', { text: kindLabel(t, reward.kind) }),
          kindHint(t, reward.kind),
          h('span', { class: 'chance', text: oneIn(t, rows, reward) }),
          removeButton(t, () => { rows.splice(index, 1); write(true); })),
        h('p', { class: 'help', text: t(`reward.${reward.kind}.help`, {}, '') }),
        kind?.param && row(t(`kind.${kind.param}`, {}, kind.param), (id) => field(kind.param, { t, id, value: reward.param,
          rerender, onChange: (v) => { reward.param = v; write(false); }, ...opts }), null,
        hint(t, `help.param_kind.${kind.param}`, { label: t(`kind.${kind.param}`, {}, kind.param) })),
        row(t('rewards.weight'), (id) => chanceChoice(t, reward.weight,
          (v) => { reward.weight = v; write(true); }, { id }), null,
        hint(t, 'help.ui.reward_weight', { label: t('rewards.weight') })));
    }),
    h('div', { class: 'type-cards' }, kinds.map((kind) => h('div', { class: 'type-card-wrap' },
      button('neutral', { class: 'type-card', onClick: () => {
        const param = opts.byKind[kind.param]?.[0]?.value ?? '';
        rows.push({ kind: kind.name, param, weight: DEFAULT_CHANCE });
        write(true);
      } }, h('b', { text: `+ ${kindLabel(t, kind.name)}` }), h('small', { text: t(`reward.${kind.name}.help`, {}, '') })),
      kindHint(t, kind.name)))));
}

// Adds `action` to the head's actions= list when it is missing (a section that needs it was just ticked).
function needAction(model, action) {
  if (!action) return;
  const list = (sheet.value(model.head, 'actions') ?? 'say').split(',').map((a) => a.trim()).filter(Boolean);
  if (!list.includes(action)) sheet.setValue(model.head, 'actions', [...list, action].join(','));
}

// Optional single section ([trade], [note]): a box adds or removes it, its form comes from the grammar.
function optionalSection(ctx, kind) {
  const { model, catalog, t, changed, rerender } = ctx;
  const grammar = catalog.section(kind);
  if (!grammar) return null;
  const current = sheet.section(model, kind);
  const panel = fold(t(`advanced.${kind}`, {}, kind), Boolean(ctx.ui[`open_${kind}`]),
    h('p', { class: 'help', text: t(`advanced.${kind}.help`, {}, '') }),
    h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: Boolean(current), onChange: (e) => {
      if (e.target.checked) {
        sheet.addSection(model, kind);
        needAction(model, SECTION_ACTIONS[kind]);
      } else sheet.removeSection(model, current);
      ctx.ui[`open_${kind}`] = true;
      changed();
      rerender();
    } }), h('span', {}, h('b', { text: t(`advanced.${kind}.enable`, {}, kind) })),
    hint(t, `help.${kind}.section`, { label: t(`advanced.${kind}`, {}, kind) })),
    current && sectionForm(ctx, current, grammar, SECTION_FORMS));
  // Kept open when the step is redrawn (a lot renamed, a place added...).
  panel.addEventListener('toggle', () => { ctx.ui[`open_${kind}`] = panel.open; });
  return panel;
}

function categoriesPanel(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  const grammar = catalog.section('category');
  if (!grammar) return null;
  const own = sheet.sectionsOf(model, 'category');
  let newId = '';
  return fold(t('advanced.category'), Boolean(ctx.ui.open_category),
    h('p', { class: 'help', text: t('advanced.category.help', { names: catalog.sharedCategories().join(', ') }) }),
    own.map((section) => h('article', { class: 'card' },
      h('header', { class: 'card-head' }, h('code', { text: section.id }),
        removeButton(t, () => { sheet.removeSection(model, section); changed(); rerender(); })),
      sectionForm(ctx, section, grammar, SECTION_FORMS))),
    h('div', { class: 'inline' },
      textInput(null, '', (v) => { newId = v; }, { placeholder: t('advanced.category.new_id'), 'aria-label': t('advanced.category.new_id') }),
      hint(t, 'help.ui.own_categories', { label: t('advanced.category') }),
      button('add', { onClick: () => {
        const id = voice.slug(newId, 'category');
        sheet.addSection(model, 'category', voice.uniqueId(model, 'category', id));
        ctx.ui.open_category = true;
        changed();
        rerender();
      } }, t('advanced.category.add'))));
}

export default {
  id: 'rewards',
  fields: [],
  blocks: ['rewards', 'trade', 'note', 'category'],
  render(ctx) {
    const { model, catalog, t } = ctx;
    const opts = fieldOptions(model, catalog, t);
    return h('div', { class: 'form' },
      h('p', { class: 'q' }, t('rewards.question'), ' ', hint(t, 'help.rewards.pool', { label: t('rewards.question') })),
      h('p', { class: 'help', text: t('rewards.help') }),
      poolEditor(ctx, opts),
      h('h3', { class: 'more', text: t('advanced.title') }),
      optionalSection(ctx, 'trade'),
      optionalSection(ctx, 'note'),
      categoriesPanel(ctx));
  },
};
