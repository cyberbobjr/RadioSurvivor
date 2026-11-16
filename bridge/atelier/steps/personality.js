// Step 3, personality: allowed actions (plain words), voices she may pass on, and the English personality text
// ([prompt], the only place of her character and past), which the bridge's AI can write from a few sentences
// (E22-T06, ai.js).

import { personalityPanel } from '../ai.js';
import { h } from '../dom.js';
import { choiceTopics, hint, withHint } from '../help.js';
import * as sheet from '../sheet.js';
import { formatList, parseList } from '../values.js';
import { checkboxes, choice, row } from '../widgets.js';

// Head key an action brings with it: shown only while the action is allowed.
const ACTION_KEYS = { share_frequency: 'shares' };

export default {
  id: 'personality',
  fields: ['actions', 'shares', 'budget'],
  blocks: ['prompt'],
  render({ model, catalog, t, voiceId, voices, ai, changed, rerender }) {
    const head = model.head;
    const writer = personalityPanel({ ai, t, voiceId, name: sheet.value(head, 'name') ?? '',
      description: sheet.description(model),
      currentPrompt: () => sheet.promptText(model),
      usePrompt: (text) => { sheet.setPromptText(model, text); changed(); rerender(); } });
    const actions = parseList(sheet.value(head, 'actions') ?? 'say');
    const options = (catalog.headerChoices('actions') ?? []).map((v) => withHint(t, 'help.head.actions', choice(t, 'action', v)));
    const others = voices.filter((v) => v.id !== voiceId && !v.removed)
      .map((v) => ({ value: v.id, label: v.name || v.id }));
    const extras = Object.entries(ACTION_KEYS).filter(([action]) => actions.includes(action)).map(([action, key]) =>
      row(t(`personality.${key}`), () => checkboxes(others, parseList(sheet.value(head, key)), (list) => {
        sheet.setValue(head, key, formatList(list));
        changed();
      }, { class: 'checks cols' }), t(`personality.${key}_help`, {}, t(`action.${action}.help`)),
      hint(t, `help.head.${key}`, { label: t(`personality.${key}`) })));
    return h('div', { class: 'form' },
      h('p', { class: 'q', text: t('personality.question') }),
      row(t('personality.actions'), () => checkboxes(options, actions, (list) => {
        sheet.setValue(head, 'actions', formatList(list));
        changed();
        rerender();
      }, { class: 'checks cols' }), t('personality.actions_help'),
      hint(t, 'help.head.actions', { label: t('personality.actions'), choices: choiceTopics('help.head.actions', options) })),
      extras,
      row(t('personality.prompt'), (id) => h('div', { class: 'stack' },
        h('textarea', { id, class: 'prompt', rows: 14, spellcheck: 'true', lang: 'en', value: sheet.promptText(model),
          onInput: (e) => { sheet.setPromptText(model, e.target.value); changed(); } }),
        h('div', { class: 'inline' }, writer.button,
          !ai.available && h('small', { class: 'muted', text: t('ai.unavailable_short') })),
        writer.panel), t('personality.prompt_help'), hint(t, 'help.ui.prompt', { label: t('personality.prompt') })));
  },
};
