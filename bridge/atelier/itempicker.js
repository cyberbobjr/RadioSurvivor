// Item search box (E22-T12): the player types a name in the page's language ("pansement", "battery") and picks one of
// the suggestions "Name — Module.Type — 0.1 kg"; the sheet stores Module.Type. Under the box: the type and the weight
// the game reads in the item script, for information. A type typed in full (Module.Type) is kept as is, so an item of
// another mod can still be written. Keyboard: arrows, Enter, Escape (WAI-ARIA combobox with a list box). With
// `browse`, a "Browse items" button next to the box opens the item browser (itembrowser.js) to pick it from a list.
// `offer` (an index of items.js, default `index`) limits the suggestions to some items (the trader's stock: the
// sellable ones); `index` still names and weighs the item written in the sheet.

import { h, uid } from './dom.js';
import { browseButton } from './itembrowser.js';
import { formatKg } from './items.js';

const TYPE_RE = /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/;

export function itemPicker(t, index, value, onChange, attrs = {}, { browse = false, offer = index } = {}) {
  const lang = t.lang;
  let current = String(value ?? '').trim();
  let results = [];
  let active = -1;
  const listId = uid('items');
  const nameOf = (type) => index.get(type, lang)?.name ?? type;
  const input = h('input', { type: 'text', value: current ? nameOf(current) : '', autocomplete: 'off', spellcheck: 'false',
    role: 'combobox', 'aria-autocomplete': 'list', 'aria-expanded': 'false', 'aria-controls': listId,
    placeholder: t('item.search_placeholder'), ...attrs });
  const list = h('ul', { id: listId, role: 'listbox', class: 'item-list', hidden: true });
  const type = h('code', { class: 'item-type' });
  const kg = h('span', { class: 'item-kg' });
  const warn = h('span', { class: 'warnline' });

  const showMeta = () => {
    const found = current ? index.get(current, lang) : null;
    type.textContent = current;
    kg.textContent = found ? formatKg(found.kg, lang) : '';
    kg.dataset.kg = found ? String(found.kg) : '';
    warn.textContent = current && !found ? t('item.unknown') : '';
  };
  const close = () => {
    list.hidden = true;
    input.setAttribute('aria-expanded', 'false');
    input.removeAttribute('aria-activedescendant');
    active = -1;
  };
  const choose = (entry) => {
    current = entry.type;
    input.value = entry.name;
    close();
    showMeta();
    onChange(current);
  };
  const highlight = (next) => {
    const options = [...list.children];
    if (!options.length) return;
    active = (next + options.length) % options.length;
    options.forEach((o, i) => o.setAttribute('aria-selected', String(i === active)));
    input.setAttribute('aria-activedescendant', options[active].id);
    options[active].scrollIntoView({ block: 'nearest' });
  };
  const open = () => {
    results = offer.search(input.value, lang);
    list.replaceChildren(...(results.length ? results.map((entry) => h('li', { id: uid('item'), role: 'option',
      'aria-selected': 'false', 'data-type': entry.type,
      onMousedown: (e) => { e.preventDefault(); choose(entry); } },
    h('b', { text: entry.name }), ' — ', h('code', { text: entry.type }), ' — ', formatKg(entry.kg, lang)))
      : [h('li', { class: 'muted', role: 'presentation', text: t('item.none') })]));
    list.hidden = input.value.trim() === '';
    input.setAttribute('aria-expanded', String(!list.hidden));
    active = -1;
  };
  // Leaving the box without picking: a full Module.Type is kept, an empty box removes the item, anything else goes
  // back to the current item.
  const settle = () => {
    close();
    const text = input.value.trim();
    if (text === (current ? nameOf(current) : '')) return;
    if (text === '' || TYPE_RE.test(text)) {
      current = text;
      onChange(current);
      if (text) input.value = nameOf(text);
    } else {
      input.value = current ? nameOf(current) : '';
    }
    showMeta();
  };

  input.addEventListener('input', open);
  input.addEventListener('blur', settle);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (list.hidden) open();
      highlight(active + (e.key === 'ArrowDown' ? 1 : -1));
      e.preventDefault();
    } else if (e.key === 'Enter' && !list.hidden && results.length) {
      choose(results[Math.max(active, 0)]);
      e.preventDefault();
    } else if (e.key === 'Escape' && !list.hidden) {
      close();
      e.stopPropagation();
    }
  });
  showMeta();
  const entry = browse ? h('div', { class: 'item-entry' }, input,
    browseButton(t, offer, { onPick: (picked) => choose(index.get(picked, lang) ?? { type: picked, name: picked }) }))
    : input;
  return h('div', { class: 'item-picker' }, entry, list, h('div', { class: 'item-meta' }, type, kg, warn));
}
