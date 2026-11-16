// Item fields of the page (E22-T12, user 2026-11-16: no item name is ever typed, the list is the only way in). An item
// already chosen is a read-only label, its name in the page's language and its weight; its Module.Type (what the sheet
// stores) is only its tooltip. A click on it opens the item browser (itembrowser.js) in single choice to replace it; an
// empty field says "Pick an item". A list of items adds its lines with "Add items", the browser in multiple choice.
// `index` (items.js) names and weighs the item written in the sheet, `offer` (default `index`) is what the browser
// lists (the trader's stock and payment: the sellable items only, said by `note`), `taken()` the types already in the
// list (shown ticked, never offered twice: the game refuses a duplicate line).

import { h, uid } from './dom.js';
import { openItemBrowser } from './itembrowser.js';
import { formatKg } from './items.js';
import { button } from './widgets.js';

const none = () => [];

// The label of one item; `label` names the field for assistive technologies ("Item 2"), `id` ties it to a <label>.
export function itemChoice(t, index, value, onChange, { offer = index, note = null, taken = none, label = null, id = null } = {}) {
  const lang = t.lang;
  let current = String(value ?? '').trim();
  const name = h('span', { id: uid('in'), class: 'item-name' });
  const kg = h('span', { class: 'item-kg' });
  const el = button('neutral', { id, class: 'item-choice', 'aria-describedby': id ? name.id : null,
    onClick: () => openItemBrowser(t, offer, { note, taken: taken().filter((type) => type !== current), onPick: (type) => {
      current = type;
      show();
      onChange(type);
    } }) }, name, kg);
  function show() {
    const found = current ? index.get(current, lang) : null;
    name.textContent = found ? found.name : t(current ? 'item.unknown' : 'item.choose');
    kg.textContent = found ? formatKg(found.kg, lang) : '';
    kg.dataset.kg = found ? String(found.kg) : '';
    el.classList.toggle('empty', !current);
    el.classList.toggle('unknown', Boolean(current) && !found);
    if (current) el.title = current; else el.removeAttribute('title');
    if (label) el.setAttribute('aria-label', t('item.choice_label', { what: label, name: name.textContent }));
  }
  show();
  return el;
}

// "Add items": the browser in multiple choice, `onAdd(types)` with the ticked ones.
export function addItemsButton(t, offer, { note = null, taken = none, onAdd }) {
  return button('add', { class: 'add-items', onClick: () => openItemBrowser(t, offer, { multi: true, note, taken: taken(), onAdd }) },
    t('browser.add_items'));
}
