// Master/detail layout of the tabs that edit one thing at a time (user 2026-11-17): the Voices tab (voicelist.js) and
// the Places tab (placestab.js). A list on the left (a column, a row of chips above the detail at phone width) and the
// thing chosen on the right. The list says nothing about what it lists: each tab gives its entries.
//
// masterDetail({id, label, side, detail}) -> the two panes side by side; masterList(host, options) draws a list.

import { h } from './dom.js';

// The two panes: `side` (an <aside>, see masterList) and `detail` (the main pane of the tab).
export function masterDetail({ id = null, label = null, side, detail }) {
  side.classList.add('side');
  detail.classList.add('main', 'md-detail');
  return h('section', { class: 'master-detail', id, 'aria-label': label, hidden: true }, side, detail);
}

// Entry to select once `removed` is gone from `ids` (the ids before the removal): the next one, the one before when it
// was the last, null when none is left or it was not listed.
export function selectionAfter(ids, removed) {
  const at = ids.indexOf(removed);
  if (at < 0) return null;
  return ids[at + 1] ?? ids[at - 1] ?? null;
}

// The list in `host`: a title, `head` (nodes under the title, e.g. "+ New"), one button per entry, then `foot`.
// entries: [{id, name, title?, lead?: node before the name, sub?: small line under the name, marks?: nodes after it}];
// `itemClass`: hook class of each button ('voice', 'place-item'); `listClass`: class of the <ul>.
export function masterList(host, { title, entries, currentId = null, onOpen, head = [], foot = [], itemClass = '',
  listClass = '' }) {
  const nav = h('nav', { 'aria-label': title }, h('ul', { class: `md-list ${listClass}`.trim() }, entries.map((entry) => {
    const on = entry.id === currentId;
    return h('li', {}, h('button', {
      type: 'button', class: `md-item ${itemClass}${on ? ' on' : ''}`.trim(), 'aria-current': on ? 'true' : null,
      title: entry.title ?? null, 'data-id': entry.id, onClick: () => onOpen(entry.id),
    }, entry.lead ?? null,
    h('span', { class: 'md-text' }, h('span', { class: 'md-name', text: entry.name }),
      entry.sub ? h('small', { class: 'md-sub', text: entry.sub }) : null),
    ...(entry.marks ?? [])));
  })));
  host.replaceChildren(h('div', { class: 'side-h', text: title }), ...head, nav, ...foot);
  // At phone width the list is a row of chips that scrolls (theme.css): the entry chosen is brought into sight.
  const on = nav.querySelector('.md-item.on');
  if (on && nav.scrollWidth > nav.clientWidth) nav.scrollLeft = Math.max(0, on.offsetLeft - 8);
}
