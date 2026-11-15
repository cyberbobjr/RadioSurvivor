// "Journal" view (E22-T10, ADR atelier-voix D09): the live lines of the bridge and of the game's console
// (GET /api/log?since=), read-only. Polls every 1.5 s while the view is shown and the browser tab is visible.
// Filters by voice, level and source; pause of the scrolling; "clear" hides the lines shown so far (this page only:
// nothing is deleted on the server, nothing is stored by the page).

import { h, select } from './dom.js';
import { button } from './widgets.js';

const POLL_MS = 1500;
const KEEP = 2000;                                     // lines kept by the page, as the server
const RANK = { debug: 0, info: 1, warning: 2, error: 3 };
const LEVEL_FILTERS = ['', 'info', 'warning', 'error'];   // '' all, else this level and the more serious ones
const SOURCES = ['', 'bridge', 'game'];

function clock(seconds) {
  return new Date(seconds * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

// api: {journal(since)}; t: strings; voiceIds(): ids of the voice list (offered in the voice filter).
export function createJournal({ api, t, voiceIds }) {
  const state = { entries: [], last: 0, clearedAt: 0, paused: false, active: false, timer: null,
    filters: { voice: '', level: '', source: '' }, seen: new Set() };
  const list = h('ol', { class: 'journal-list', 'aria-live': 'off' });
  const note = h('div', { class: 'journal-notes' });
  const count = h('span', { class: 'muted journal-count' });
  const voiceHost = h('span', {});
  const pause = button('neutral', { id: 'journal-pause', 'aria-pressed': 'false',
    onClick: () => setPaused(!state.paused) }, t('journal.pause'));

  const shown = (e) => e.seq > state.clearedAt
    && (!state.filters.voice || e.voice === state.filters.voice)
    && (!state.filters.source || e.source === state.filters.source)
    && (!state.filters.level || RANK[e.level] >= RANK[state.filters.level]);

  function row(e) {
    return h('li', { class: `jrow ${e.level} ${e.source}` },
      h('span', { class: 'jtime', text: clock(e.time) }),
      h('span', { class: `jsrc ${e.source}`, text: t(`journal.source.${e.source}`, {}, e.source) }),
      h('span', { class: `jlvl ${e.level}`, text: t(`journal.level.${e.level}`, {}, e.level) }),
      h('span', { class: 'jvoice', text: e.voice ?? '' }),
      h('span', { class: 'jtext', text: e.text }));
  }

  function scrollDown() {
    if (!state.paused) list.scrollTop = list.scrollHeight;
  }

  function renderVoiceFilter() {
    const ids = [...new Set([...voiceIds(), ...state.seen])].sort();
    voiceHost.replaceChildren(select([{ value: '', label: t('journal.all_voices') }, ...ids.map((id) => ({ value: id, label: id }))],
      state.filters.voice, (v) => { state.filters.voice = v; renderAll(); }, { id: 'journal-voice', 'aria-label': t('journal.voice') }));
  }

  function renderCount() {
    const visible = list.childElementCount;
    count.textContent = t('journal.count', { n: visible });
  }

  function renderAll() {
    const rows = state.entries.filter(shown).map(row);
    list.replaceChildren(...(rows.length ? rows : [h('li', { class: 'jempty', text: t('journal.empty') })]));
    renderCount();
    scrollDown();
  }

  function add(entries) {
    if (!entries.length) return;
    const newVoices = entries.some((e) => e.voice && !state.seen.has(e.voice));
    entries.forEach((e) => { if (e.voice) state.seen.add(e.voice); });
    state.entries.push(...entries);
    if (state.entries.length > KEEP) state.entries.splice(0, state.entries.length - KEEP);
    if (newVoices) renderVoiceFilter();
    const rows = entries.filter(shown).map(row);
    if (!rows.length) return;
    list.querySelector('.jempty')?.remove();
    list.append(...rows);
    while (list.childElementCount > KEEP) list.firstElementChild.remove();
    renderCount();
    scrollDown();
  }

  function renderNotes(result) {
    const lines = [];
    if (!result.bridge) lines.push(t('journal.no_bridge'));
    if (!result.gameLog) lines.push(t('journal.no_game_log'));
    else if (!result.gameLogFound) lines.push(t('journal.game_log_missing', { path: result.gameLog }));
    note.replaceChildren(...lines.map((text) => h('p', { class: 'journal-note', text })));
  }

  async function tick() {
    state.timer = null;
    if (!state.active || document.hidden) return;
    const result = await api.journal(state.last);
    if (result.ok) {
      const entries = result.entries ?? [];
      if (entries.length && entries[0].seq <= state.last) {   // the bridge restarted: its numbering too
        state.entries = [];
        state.clearedAt = 0;
        list.replaceChildren();
      }
      state.last = result.last ?? state.last;
      add(entries);
      renderNotes(result);
    }
    if (state.active && !document.hidden) state.timer = setTimeout(tick, POLL_MS);
  }

  function setPaused(paused) {
    state.paused = paused;
    pause.textContent = paused ? t('journal.resume') : t('journal.pause');
    pause.setAttribute('aria-pressed', String(paused));
    scrollDown();
  }

  function start() {
    state.active = true;
    renderVoiceFilter();
    if (!state.timer) tick();
  }

  function stop() {
    state.active = false;
    clearTimeout(state.timer);
    state.timer = null;
  }

  document.addEventListener('visibilitychange', () => { if (state.active && !document.hidden && !state.timer) tick(); });

  const filter = (id, label, values, key, prefix) => h('label', { class: 'inline', for: id }, label,
    select(values.map((v) => ({ value: v, label: t(`${prefix}${v || 'all'}`) })), state.filters[key],
      (v) => { state.filters[key] = v; renderAll(); }, { id }));

  const el = h('section', { class: 'journal', id: 'journal', 'aria-label': t('tab.journal') },
    h('div', { class: 'toolbar' },
      h('div', { class: 'title' }, h('h2', { text: t('journal.title') }), count),
      h('div', { class: 'btns' }, pause,
        button('neutral', { id: 'journal-clear', onClick: () => {
          state.clearedAt = state.last;
          renderAll();
        } }, t('journal.clear')))),
    h('p', { class: 'help', text: t('journal.help') }),
    note,
    h('div', { class: 'btns journal-filters' },
      h('label', { class: 'inline', for: 'journal-voice' }, t('journal.voice'), voiceHost),
      filter('journal-level', t('journal.level'), LEVEL_FILTERS, 'level', 'journal.levels.'),
      filter('journal-source', t('journal.source'), SOURCES, 'source', 'journal.sources.')),
    list);
  renderAll();
  return { el, start, stop };
}
