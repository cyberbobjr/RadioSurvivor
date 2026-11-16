// Left column: the voices of the working folder (GET /api/voices) with a coloured dot for their state, a red mark
// when the game refused the sheet (GET /api/verdicts, E22-T04), the "+ New voice" button and a one-line legend.

import { h } from './dom.js';
import { button } from './widgets.js';

// State of a voice entry of the server: removed, created by the player, delivered and changed, an older delivered
// version the game wrote (it replaces it at the next world load), delivered as is.
export function voiceStatus(entry) {
  if (!entry) return 'custom';
  if (entry.removed) return 'removed';
  if (entry.custom) return 'custom';
  if (entry.modified) return 'modified';
  return entry.outdated ? 'outdated' : 'delivered';
}

export const STATUSES = ['custom', 'delivered', 'outdated', 'modified', 'removed'];

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
    // S07: one line of legend; each voice says its state in its tooltip.
    h('p', { class: 'legend' }, h('span', { class: 'gamebad', 'aria-hidden': 'true' }), t('verdict.dot')));
}
