// Step 3, what she knows: knows / ignores / secret lists, allowed actions (plain words), voices she may pass on, and
// the English personality text ([prompt]), which the bridge's AI can write from a few sentences (E22-T06, ai.js).

import { personalityPanel } from '../ai.js';
import { h } from '../dom.js';
import { choiceTopics, hint, withHint } from '../help.js';
import * as sheet from '../sheet.js';
import { formatList, parseList } from '../values.js';
import { checkboxes, choice, listEditor, row } from '../widgets.js';

// Head key an action brings with it: shown only while the action is allowed.
const ACTION_KEYS = { share_frequency: 'shares' };

export default {
  id: 'knows',
  fields: ['knows', 'ignores', 'secret', 'actions', 'shares', 'budget'],
  blocks: ['prompt'],
  render({ model, catalog, t, voiceId, voices, ai, changed, rerender }) {
    const head = model.head;
    const writer = personalityPanel({ ai, t, voiceId, name: sheet.value(head, 'name') ?? '',
      description: sheet.description(model),
      lists: () => ({ knows: sheet.values(head, 'knows'), ignores: sheet.values(head, 'ignores'), secret: sheet.values(head, 'secret') }),
      currentPrompt: () => sheet.promptText(model),
      usePrompt: (text) => { sheet.setPromptText(model, text); changed(); rerender(); } });
    const lists = ['knows', 'ignores', 'secret'].map((key) => row(t(`knows.${key}`),
      () => listEditor(t, sheet.values(head, key), (list) => { sheet.setValues(head, key, list); changed(); },
        t(`knows.${key}_placeholder`)), t(`knows.${key}_help`), hint(t, `help.head.${key}`, { label: t(`knows.${key}`) })));
    const actions = parseList(sheet.value(head, 'actions') ?? 'say');
    const options = (catalog.headerChoices('actions') ?? []).map((v) => withHint(t, 'help.head.actions', choice(t, 'action', v)));
    const others = voices.filter((v) => v.id !== voiceId && !v.removed)
      .map((v) => ({ value: v.id, label: v.name || v.id }));
    const extras = Object.entries(ACTION_KEYS).filter(([action]) => actions.includes(action)).map(([action, key]) =>
      row(t(`knows.${key}`), () => checkboxes(others, parseList(sheet.value(head, key)), (list) => {
        sheet.setValue(head, key, formatList(list));
        changed();
      }, { class: 'checks cols' }), t(`knows.${key}_help`, {}, t(`action.${action}.help`)),
      hint(t, `help.head.${key}`, { label: t(`knows.${key}`) })));
    return h('div', { class: 'form' },
      h('p', { class: 'q', text: t('knows.question') }),
      lists,
      row(t('knows.actions'), () => checkboxes(options, actions, (list) => {
        sheet.setValue(head, 'actions', formatList(list));
        changed();
        rerender();
      }, { class: 'checks cols' }), t('knows.actions_help'),
      hint(t, 'help.head.actions', { label: t('knows.actions'), choices: choiceTopics('help.head.actions', options) })),
      extras,
      row(t('knows.prompt'), (id) => h('div', { class: 'stack' },
        h('textarea', { id, class: 'prompt', rows: 14, spellcheck: 'true', lang: 'en', value: sheet.promptText(model),
          onInput: (e) => { sheet.setPromptText(model, e.target.value); changed(); } }),
        h('div', { class: 'inline' }, writer.button,
          !ai.available && h('small', { class: 'muted', text: t('ai.unavailable_short') })),
        writer.panel), t('knows.prompt_help'), hint(t, 'help.ui.prompt', { label: t('knows.prompt') })));
  },
};
