// Item browser (user 2026-11-15, 2026-11-16: no item name is ever typed): the only way the page picks items of the
// game, an in-page <dialog>. A search box (name in the page's language first, then the other language; accents and case
// ignored, items.js), a category filter (the game's inventory categories) and a scrolling list showing each item's name
// in the page's language, its category and its weight; the item's Module.Type is only its tooltip.
// - multi (a list of items: stock, payment, own category): each line has a check box, a click or Enter ticks it, the
//   ticks survive a new search or category; "Add selected" gives the ticked types to `onAdd(types)` and closes. An item
//   already in the list (`taken`) is shown ticked and cannot be ticked again (the game refuses a duplicate line).
// - single (one item: a mission's item, a line replaced): a click or Enter gives its type to `onPick(type)` and closes.
// Escape or "Close" close it without change; the focus goes back to the button that opened it. `note` (an i18n key)
// says under the filters which items the list holds when it is not every item of the game (sellable ones only).
// `words` (E24-T03) is the i18n prefix of its texts (`browser` for items, `lootbrowser` for the loot lists of a
// note): a text missing under it falls back to `browser.<key>`; `index` is any list with the item index contract
// (items.js: find, categories), such as the loot lists (lootindex.js).

import { h, select, uid } from './dom.js';
import { hint } from './help.js';
import { button } from './widgets.js';

const MAX_SHOWN = 200;

export function openItemBrowser(t, index, { multi = false, note = null, taken = [], onPick = null, onAdd = null,
  words = 'browser' } = {}) {
  const lang = t.lang;
  const w = (key, args = {}) => t(`${words}.${key}`, args, t(`browser.${key}`, args));
  const helpTopic = (name) => (t.has?.(`help.ui.${words}_${name}.what`) ? `help.ui.${words}_${name}` : `help.ui.item_${name}`);
  const opener = document.activeElement;
  const titleId = uid('ib');
  const listId = uid('ibl');
  const already = new Set(taken);
  const ticked = new Set();
  let shown = [];
  let active = -1;

  const search = h('input', { type: 'search', autocomplete: 'off', spellcheck: 'false', role: 'combobox',
    'aria-autocomplete': 'list', 'aria-expanded': 'true', 'aria-controls': listId, 'aria-label': w('search'),
    placeholder: w('search_placeholder'), class: 'browser-search' });
  const category = select([{ value: '', label: w('all_categories') }, ...index.categories(lang)], '',
    () => refresh(), { 'aria-label': w('category'), class: 'browser-category' });
  const count = h('p', { class: 'browser-count', 'aria-live': 'polite' });
  const status = h('p', { class: 'browser-selected', 'aria-live': 'polite' });
  const list = h('ul', { id: listId, role: 'listbox', class: `browser-list${multi ? ' multi' : ''}`,
    'aria-label': w('results'), 'aria-multiselectable': multi ? 'true' : null });
  const addButton = multi ? button('primary', { class: 'browser-add', disabled: true, onClick: () => {
    onAdd([...ticked]);
    dialog.close();
  } }, w('add_selected', { n: 0 })) : null;

  const rows = () => [...list.querySelectorAll('[role=option]')];
  const setActive = (next, scroll = true) => {
    const all = rows();
    if (!all.length) { active = -1; return; }
    active = Math.min(Math.max(next, 0), all.length - 1);
    all.forEach((r, i) => {
      r.classList.toggle('active', i === active);
      if (!multi) r.setAttribute('aria-selected', String(i === active));
    });
    search.setAttribute('aria-activedescendant', all[active].id);
    if (scroll) all[active].scrollIntoView({ block: 'nearest' });
  };
  const showTicked = () => {
    status.textContent = ticked.size ? w('selected', { n: ticked.size }) : '';
    addButton.disabled = ticked.size === 0;
    addButton.textContent = w('add_selected', { n: ticked.size });
  };
  const toggle = (entry, row) => {
    if (ticked.has(entry.type)) ticked.delete(entry.type); else ticked.add(entry.type);
    const on = ticked.has(entry.type);
    row.setAttribute('aria-selected', String(on));
    row.querySelector('input').checked = on;
    showTicked();
  };
  const choose = (entry, row) => {
    if (already.has(entry.type)) return;
    if (multi) { toggle(entry, row); return; }
    onPick(entry.type);
    dialog.close();
  };
  const rowOf = (entry, i) => {
    const isTaken = already.has(entry.type);
    const on = isTaken || ticked.has(entry.type);
    return h('li', { id: `${listId}-${i}`, role: 'option', 'aria-selected': String(multi ? on : false),
      'aria-disabled': isTaken ? 'true' : null, class: isTaken ? 'taken' : null, 'data-type': entry.type,
      title: entry.type, onMousedown: (e) => e.preventDefault(),
      onClick: (e) => { setActive(i, false); choose(entry, e.currentTarget); } },
    multi && h('input', { type: 'checkbox', tabindex: '-1', 'aria-hidden': 'true', checked: on, disabled: isTaken }),
    h('span', { class: 'b-name', text: entry.name }),
    h('span', { class: 'b-cat', text: entry.catName }),
    h('span', { class: 'b-pick', 'aria-hidden': 'true',
      text: isTaken ? w('taken') : (multi ? '' : w('pick')) }));
  };

  function refresh() {
    const { items, total } = index.find(search.value, lang, { category: category.value, limit: MAX_SHOWN });
    shown = items;
    list.replaceChildren(...(items.length ? items.map(rowOf)
      : [h('li', { class: 'muted', role: 'presentation', text: w('none') })]));
    count.textContent = total > items.length ? w('more', { shown: items.length, n: total })
      : w('count', { n: total });
    search.removeAttribute('aria-activedescendant');
    active = -1;
    list.scrollTop = 0;
  }

  search.addEventListener('input', refresh);
  search.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      setActive(active + (e.key === 'ArrowDown' ? 1 : -1));
      e.preventDefault();
    } else if (e.key === 'Escape') {
      dialog.close();          // a search box would first only empty itself: Escape always closes the browser
      e.preventDefault();
    } else if (e.key === 'Enter' && shown.length) {
      const i = Math.max(active, 0);
      setActive(i, false);
      choose(shown[i], rows()[i]);
      e.preventDefault();
    }
  });

  const close = () => dialog.close();
  const dialog = h('dialog', { class: `item-browser${multi ? ' multi' : ''}`, 'aria-labelledby': titleId },
    h('article', { class: note ? 'with-note' : null },
      h('header', { class: 'browser-head' },
        h('h2', { id: titleId, text: t(multi ? 'browser.title_multi' : 'browser.title') }),
        multi && h('small', { class: 'muted', text: w('enter_tip') }),
        hint(t, helpTopic('browser'), { label: w('title') }),
        button('icon', { class: 'browser-close', 'aria-label': w('close'), title: w('close'),
          onClick: close }, '✕')),
      h('div', { class: 'browser-filters' }, search,
        h('div', { class: 'browser-cat' }, category, hint(t, helpTopic('category'), { label: w('category') }))),
      note && h('p', { class: 'browser-note', text: t(note) }),
      h('div', { class: 'browser-cols', 'aria-hidden': 'true' }, multi && h('span'),
        h('span', { text: w('col_name') }), h('span', { text: w('col_category') }),
        h('span')),
      list,
      h('footer', { class: 'browser-foot' }, count, status,
        h('div', { class: 'browser-actions' },
          button('neutral', { class: 'browser-cancel', onClick: close }, w('close')), addButton))));
  dialog.addEventListener('close', () => {
    dialog.remove();
    if (opener && opener.isConnected) opener.focus();
  });
  document.body.append(dialog);
  refresh();
  if (multi) showTicked();
  dialog.showModal();
  search.focus();
  return dialog;
}
