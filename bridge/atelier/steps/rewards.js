// Step 5, rewards: the pool of [rewards] built from the reward kinds of the catalogue (with the field of their
// parameter kind), each with how often it comes out (Rarely / Normally / Often), where a hidden reward is left
// (cache_place=, a shared point, E25-T03) when a kind of the pool needs it, then the optional advanced panels,
// closed by default: trade ([trade]), frequency note ([note]) and the voice's own categories ([category]), all
// generated from the section grammar, the keys with a form of their own registered in stock.js; the own categories
// are folded under "Advanced options" (E24-T02).

import { inputPropose } from '../ai.js';
import { h } from '../dom.js';
import { field, fieldOptions } from '../fields.js';
import { hint } from '../help.js';
import { placeSelect } from '../placeform.js';
import { sectionForm } from '../sectionform.js';
import * as sheet from '../sheet.js';
import { SECTION_ACTIONS, SECTION_FORMS } from '../stock.js';
import { DEFAULT_CHANCE } from '../values.js';
import * as voice from '../voice.js';
import { button, chanceChoice, fold, removeButton, row, textInput } from '../widgets.js';

const kindLabel = (t, kind) => t(`reward.${kind}`, {}, kind);
const kindIcon = (t, kind) => t(`reward.${kind}.icon`, {}, '');
// First choice of a new reward's parameter by kind (charter: a useful default), else the first of the list.
const PREFERRED = { category: 'food' };
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
          h('b', { text: `${kindIcon(t, reward.kind)} ${kindLabel(t, reward.kind)}`.trim() }),
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
        const choices = opts.byKind[kind.param] ?? [];
        const param = (choices.find((c) => c.value === PREFERRED[kind.param]) ?? choices[0])?.value ?? '';
        rows.push({ kind: kind.name, param, weight: DEFAULT_CHANCE });
        write(true);
      } }, h('span', { class: 'card-icon', 'aria-hidden': 'true', text: kindIcon(t, kind.name) }),
      h('b', { text: `+ ${kindLabel(t, kind.name)}` }), h('small', { text: t(`reward.${kind.name}.help`, {}, '') })),
      kindHint(t, kind.name)))));
}

// Where a reward that is hidden in the world is left (a kind of the catalogue that declares `place`: the cache).
function cachePlaceRow(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  const rewards = sheet.section(model, 'rewards');
  if (!rewards || !voice.pool(model).some((r) => catalog.rewardKind(r.kind)?.place)) return null;
  const label = h('span', {}, t('rewards.cache_place'), h('span', { class: 'pill-needed', text: t('field.needed') }));
  return row(label, (id) => placeSelect(ctx, sheet.value(rewards, 'cache_place') ?? '', (v) => {
    voice.setCachePlace(model, v);
    changed();
    rerender();
  }, { points: true, empty: t('field.choose'), id }), t('rewards.cache_place_help'),
  hint(t, 'help.rewards.cache_place', { label: t('rewards.cache_place') }));
}

// Adds `action` to the head's actions= list when it is missing (a section that needs it was just ticked); true when it
// was added (the panel says so).
function needAction(model, action) {
  if (!action) return false;
  const list = (sheet.value(model.head, 'actions') ?? 'say').split(',').map((a) => a.trim()).filter(Boolean);
  if (list.includes(action)) return false;
  sheet.setValue(model.head, 'actions', [...list, action].join(','));
  return true;
}

// Optional single section ([trade], [note]): a box adds or removes it, its form comes from the grammar.
function optionalSection(ctx, kind) {
  const { model, catalog, t, changed, rerender } = ctx;
  const grammar = catalog.section(kind);
  if (!grammar) return null;
  const current = sheet.section(model, kind);
  const panel = fold(`${t(`advanced.${kind}.icon`, {}, '')} ${t(`advanced.${kind}`, {}, kind)}`.trim(), Boolean(ctx.ui[`open_${kind}`]),
    h('p', { class: 'help', text: t(`advanced.${kind}.help`, {}, '') }),
    h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: Boolean(current), onChange: (e) => {
      if (e.target.checked) {
        sheet.addSection(model, kind);
        ctx.ui[`added_${kind}`] = needAction(model, SECTION_ACTIONS[kind]);
      } else sheet.removeSection(model, current);
      ctx.ui[`open_${kind}`] = true;
      changed();
      rerender();
    } }), h('span', {}, h('b', { text: t(`advanced.${kind}.enable`, {}, kind) })),
    hint(t, `help.${kind}.section`, { label: t(`advanced.${kind}`, {}, kind) })),
    current && ctx.ui[`added_${kind}`] && h('p', { class: 'okline', text: t('advanced.action_added',
      { action: t(`action.${SECTION_ACTIONS[kind]}`) }) }),
    current && sectionForm(ctx, current, grammar, SECTION_FORMS));
  // Kept open when the step is redrawn (a lot renamed, a place added...).
  panel.addEventListener('toggle', () => { ctx.ui[`open_${kind}`] = panel.open; });
  return panel;
}

// The voice's own item lists ([category <id>], user decision 2026-11-16: folded under "Advanced options"): the author
// types a name, the id is made from it and never shown (voice.labelOf shows it back).
function categoriesPanel(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  const grammar = catalog.section('category');
  if (!grammar) return null;
  const own = sheet.sectionsOf(model, 'category');
  let newName = '';
  const nameInput = textInput(null, '', (v) => { newName = v; }, { placeholder: t('advanced.category.new_name'),
    'aria-label': t('advanced.category.new_name') });
  const panel = fold(t('advanced.category'), Boolean(ctx.ui.open_category),
    h('p', { class: 'help', text: t('advanced.category.help') }),
    own.map((section) => h('article', { class: 'card', title: section.id },
      h('header', { class: 'card-head' }, h('b', { text: voice.labelOf(section.id) }),
        removeButton(t, () => { sheet.removeSection(model, section); changed(); rerender(); })),
      sectionForm(ctx, section, grammar, SECTION_FORMS))),
    h('div', { class: 'inline' }, nameInput,
      inputPropose(ctx, 'category_name', nameInput,
        { details: () => ({ other_lists: own.map((c) => voice.labelOf(c.id)).join(', ') }) }),
      hint(t, 'help.ui.own_categories', { label: t('advanced.category') }),
      button('add', { onClick: () => {
        // A name of the mod's shared categories is refused by the game for an own one: the next free id.
        const taken = new Set([...catalog.sharedCategories(), ...own.map((c) => c.id)]);
        const base = voice.slug(newName, 'category');
        let id = base;
        for (let n = 2; taken.has(id); n += 1) id = `${base}_${n}`;
        sheet.addSection(model, 'category', id);
        ctx.ui.open_category = true;
        changed();
        rerender();
      } }, t('advanced.category.add'))));
  panel.addEventListener('toggle', () => { ctx.ui.open_category = panel.open; });
  return panel;
}

export default {
  id: 'rewards',
  fields: [],
  blocks: ['rewards', 'trade', 'note', 'category'],
  render(ctx) {
    const { t } = ctx;
    const opts = fieldOptions(ctx, t);
    return h('div', { class: 'form' },
      h('p', { class: 'q' }, t('rewards.question'), ' ', hint(t, 'help.rewards.pool', { label: t('rewards.question') })),
      h('p', { class: 'help', text: t('rewards.help') }),
      poolEditor(ctx, opts),
      cachePlaceRow(ctx),
      h('h3', { class: 'more', text: t('advanced.title') }),
      h('div', { class: 'more-cards' }, optionalSection(ctx, 'trade'), optionalSection(ctx, 'note')),
      fold(t('advanced.options'), Boolean(ctx.ui.open_category), categoriesPanel(ctx)));
  },
};
