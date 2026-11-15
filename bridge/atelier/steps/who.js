// Step 1, who: id (new voice only), name, short description (leading comment of the sheet), life state.

import { h, select } from '../dom.js';
import { choiceTopics, hint, selectHelp } from '../help.js';
import * as sheet from '../sheet.js';
import { choice, row, textInput } from '../widgets.js';

export default {
  id: 'who',
  fields: ['format', 'id', 'name', 'language', 'state'],
  render({ model, catalog, t, isNew, changed }) {
    const head = model.head;
    const set = (key) => (v) => { sheet.setValue(head, key, v); changed(); };
    const states = (catalog.headerChoices('state') ?? []).map((v) => choice(t, 'choice.state', v));
    return h('div', { class: 'form' },
      h('p', { class: 'q', text: t('who.question') }),
      row(t('who.name'), (id) => textInput(id, sheet.value(head, 'name'), set('name'),
        { placeholder: t('who.name_placeholder'), autocomplete: 'off' }), null,
      hint(t, 'help.head.name', { label: t('who.name') })),
      row(t('who.id'), (id) => textInput(id, sheet.value(head, 'id'), set('id'),
        { readonly: !isNew, spellcheck: 'false', autocomplete: 'off', pattern: '[a-z][a-z0-9_]{0,31}' }),
      isNew ? t('who.id_help') : t('who.id_locked'), hint(t, 'help.head.id', { label: t('who.id') })),
      row(t('who.description'), (id) => h('textarea', { id, rows: 8, class: 'description', value: sheet.description(model),
        placeholder: t('who.description_placeholder'),
        onInput: (e) => { sheet.setDescription(model, e.target.value); changed(); } }), t('who.description_help'),
      hint(t, 'help.ui.description', { label: t('who.description') })),
      row(t('who.state'), (id) => {
        const field = select(states, sheet.value(head, 'state') ?? 'active', set('state'), { id });
        return h('div', { class: 'stack' }, field, selectHelp(t, 'help.head.state', field));
      }, null, hint(t, 'help.head.state', { label: t('who.state'), choices: choiceTopics('help.head.state', states) })));
  },
};
