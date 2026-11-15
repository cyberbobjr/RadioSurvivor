// Item browser (user 2026-11-15): an in-page <dialog> to pick items of the game from a list instead of typing their
// name. A search box (name in the page's language first, then the other language, then Module.Type; accents and case
// ignored, items.js), a category filter (the game's inventory categories) and a scrolling list showing each item's name
// in the page's language, its category, Module.Type and weight. A click or Enter picks the item: one pick closes the
// dialog, or, with `multi` (the trader's stock), each pick is added and the dialog stays open with the count of added
// items. Escape, "Close" or "Done" close it; the focus goes back to the button that opened it.

import { h, select, uid } from './dom.js';
import { hint } from './help.js';
import { formatKg } from './items.js';
import { button } from './widgets.js';

const MAX_SHOWN = 200;

// Opens the browser over the page. `onPick(type)` is called for each item picked.
export function openItemBrowser(t, index, { multi = false, onPick }) {
  const lang = t.lang;
  const opener = document.activeElement;
  const titleId = uid('ib');
  const listId = uid('ibl');
  let shown = [];
  let active = -1;
  let added = 0;

  const search = h('input', { type: 'search', autocomplete: 'off', spellcheck: 'false', role: 'combobox',
    'aria-autocomplete': 'list', 'aria-expanded': 'true', 'aria-controls': listId, 'aria-label': t('browser.search'),
    placeholder: t('browser.search_placeholder'), class: 'browser-search' });
  const category = select([{ value: '', label: t('browser.all_categories') }, ...index.categories(lang)], '',
    () => refresh(), { 'aria-label': t('browser.category'), class: 'browser-category' });
  const count = h('p', { class: 'browser-count', 'aria-live': 'polite' });
  const status = h('p', { class: 'browser-added', 'aria-live': 'polite' });
  const list = h('ul', { id: listId, role: 'listbox', class: 'browser-list', 'aria-label': t('browser.results') });

  const setActive = (next, scroll = true) => {
    const rows = [...list.querySelectorAll('[role=option]')];
    if (!rows.length) { active = -1; return; }
    active = Math.min(Math.max(next, 0), rows.length - 1);
    rows.forEach((r, i) => r.setAttribute('aria-selected', String(i === active)));
    search.setAttribute('aria-activedescendant', rows[active].id);
    if (scroll) rows[active].scrollIntoView({ block: 'nearest' });
  };
  const pick = (entry, row) => {
    onPick(entry.type);
    if (!multi) { dialog.close(); return; }
    added += 1;
    status.textContent = t('browser.added', { n: added });
    row?.classList.add('picked');
  };
  const rowOf = (entry, i) => h('li', { id: `${listId}-${i}`, role: 'option', 'aria-selected': 'false',
    'data-type': entry.type, onMousedown: (e) => e.preventDefault(),
    onClick: (e) => { setActive(i, false); pick(entry, e.currentTarget); } },
  h('span', { class: 'b-name', text: entry.name }),
  h('span', { class: 'b-cat', text: entry.catName }),
  h('code', { class: 'b-type', text: entry.type }),
  h('span', { class: 'b-kg', text: formatKg(entry.kg, lang) }),
  h('span', { class: 'b-pick', 'aria-hidden': 'true', text: t(multi ? 'browser.add' : 'browser.pick') }));

  function refresh() {
    const { items, total } = index.find(search.value, lang, { category: category.value, limit: MAX_SHOWN });
    shown = items;
    list.replaceChildren(...(items.length ? items.map(rowOf)
      : [h('li', { class: 'muted', role: 'presentation', text: t('browser.none') })]));
    count.textContent = total > items.length ? t('browser.more', { shown: items.length, n: total })
      : t('browser.count', { n: total });
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
      pick(shown[i], list.querySelectorAll('[role=option]')[i]);
      e.preventDefault();
    }
  });

  const close = () => dialog.close();
  const dialog = h('dialog', { class: 'item-browser', 'aria-labelledby': titleId },
    h('article', {},
      h('header', { class: 'browser-head' },
        h('h2', { id: titleId, text: t(multi ? 'browser.title_multi' : 'browser.title') }),
        hint(t, 'help.ui.item_browser', { label: t('browser.open') }),
        button('icon', { class: 'browser-close', 'aria-label': t('browser.close'), title: t('browser.close'),
          onClick: close }, '✕')),
      h('div', { class: 'browser-filters' }, search,
        h('div', { class: 'browser-cat' }, category, hint(t, 'help.ui.item_category', { label: t('browser.category') }))),
      h('div', { class: 'browser-cols', 'aria-hidden': 'true' },
        h('span', { text: t('browser.col_name') }), h('span', { text: t('browser.col_category') }),
        h('span', { text: t('browser.col_type') }), h('span', { text: t('browser.col_kg') }), h('span')),
      list,
      h('footer', { class: 'browser-foot' }, count, status,
        button(multi ? 'primary' : 'neutral', { class: 'browser-done', onClick: close },
          t(multi ? 'browser.done' : 'browser.close')))));
  dialog.addEventListener('close', () => {
    dialog.remove();
    if (opener && opener.isConnected) opener.focus();
  });
  document.body.append(dialog);
  refresh();
  dialog.showModal();
  search.focus();
  return dialog;
}

// "Browse items" button opening the browser (`multi`: keeps it open, one onPick per item).
export function browseButton(t, index, options) {
  return button('neutral', { class: 'browse-items', onClick: () => openItemBrowser(t, index, options) },
    t('browser.open'));
}
