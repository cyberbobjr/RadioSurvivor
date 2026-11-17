// Step 1, who: name, short description (leading comment of the sheet), life state as cards. The voice's id is made from
// its name when it is created and never shown (E24-T02, charter rule 1).

import { withPropose } from '../ai.js';
import { h } from '../dom.js';
import { hint } from '../help.js';
import * as sheet from '../sheet.js';
import { cards, choice, row, textInput } from '../widgets.js';

export default {
  id: 'who',
  fields: ['format', 'id', 'name', 'state'],
  render(ctx) {
    const { model, catalog, t, changed } = ctx;
    const head = model.head;
    const set = (key) => (v) => { sheet.setValue(head, key, v); changed(); };
    const states = (catalog.headerChoices('state') ?? []).map((v) => ({ ...choice(t, 'choice.state', v),
      icon: t(`choice.state.${v}.icon`, {}, '') || null }));
    return h('div', { class: 'form' },
      row(t('who.name'), (id) => withPropose(ctx, 'name', textInput(id, sheet.value(head, 'name'), set('name'),
        { placeholder: t('who.name_placeholder'), autocomplete: 'off' })), null,
      hint(t, 'help.head.name', { label: t('who.name') })),
      row(t('who.description'), (id) => withPropose(ctx, 'description', textInput(id, sheet.description(model), (v) => {
        sheet.setDescription(model, v);
        changed();
      }, { class: 'description', placeholder: t('who.description_placeholder') })), t('who.description_help'),
      hint(t, 'help.ui.description', { label: t('who.description') })),
      row(t('who.state'), (id) => cards('state', states, sheet.value(head, 'state') ?? 'active', set('state'), { id }),
        null, hint(t, 'help.head.state', { label: t('who.state') })));
  },
};
