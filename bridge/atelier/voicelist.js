// Left column: the voices of the working folder (GET /api/voices) with a coloured dot for their state, a red mark
// when the game refused the sheet (GET /api/verdicts, E22-T04), the "+ New voice" button and the legend.

import { h } from './dom.js';
import { button } from './widgets.js';

// State of a voice entry of the server: removed, created by the player, delivered and changed, delivered as is.
export function voiceStatus(entry) {
  if (!entry) return 'custom';
  if (entry.removed) return 'removed';
  if (entry.custom) return 'custom';
  return entry.modified ? 'modified' : 'delivered';
}

export const STATUSES = ['custom', 'delivered', 'modified', 'removed'];

export const refusedByGame = (verdicts, id) => verdicts?.[id]?.state === 'refused';

export function renderVoiceList(host, { t, voices, currentId, onOpen, onNew, verdicts = {} }) {
  host.replaceChildren(
    h('div', { class: 'side-h', text: t('voices.title') }),
    h('nav', { 'aria-label': t('voices.title') }, h('ul', { class: 'voices' }, voices.map((entry) => {
      const status = voiceStatus(entry);
      return h('li', {}, h('button', {
        type: 'button', class: `voice${entry.id === currentId ? ' on' : ''}`, 'aria-current': entry.id === currentId ? 'true' : null,
        title: t(`status.${status}.help`), onClick: () => onOpen(entry.id),
      }, h('span', { class: `dot ${status}`, 'aria-hidden': 'true' }),
      h('span', { class: 'vname', text: entry.name || entry.id }),
      refusedByGame(verdicts, entry.id) && h('span', { class: 'gamebad', title: t('verdict.dot'), 'aria-hidden': 'true' }),
      h('span', { class: 'sr', text: ` (${t(`status.${status}`)})` }),
      refusedByGame(verdicts, entry.id) && h('span', { class: 'sr', text: ` (${t('verdict.dot')})` })));
    }))),
    button('add', { id: 'new-voice', class: 'new', onClick: onNew }, t('voices.new')),
    h('ul', { class: 'legend' }, STATUSES.map((status) => h('li', {},
      h('span', { class: `dot ${status}`, 'aria-hidden': 'true' }), t(`status.${status}`))),
    h('li', {}, h('span', { class: 'gamebad', 'aria-hidden': 'true' }), t('verdict.dot'))));
}
