// "Places" view (E25-T03, ADR lieux communs D02, D06-D08): the places every voice shares (personas/_places.txt), as a
// master/detail (masterdetail.js, user 2026-11-17): the list of the places on the left ("+ New place" on top, the
// number of voices using each), the form of the place chosen on the right: its name, a spot or an area, its square or
// its corners pasted from the map, and the voices that use it (a click opens the voice); a place a voice uses cannot be
// deleted (the voices are named). With no place chosen, the right pane is the tab's home: what a place is and the
// places recorded in game (surveys.js), reached again by the last button of the list. Every change is saved by itself
// once the place is finished (placestore.js): there is no file to save by hand.
//
// createPlacesView({api, t, catalog, ai, toast, store, current, open}) -> {el, start, stop}; current(): the voice open
// in the editor {id, name, model} (unsaved), counted as a user of the places it names; open(id): opens a voice.

import { confirmBar } from './dialogs.js';
import { append, clear, h } from './dom.js';
import { hint } from './help.js';
import { masterDetail, masterList, selectionAfter } from './masterdetail.js';
import { newPlaceDialog, placeFields } from './placeform.js';
import * as places from './places.js';
import * as sheet from './sheet.js';
import { surveysBlock } from './surveys.js';
import { button, removeButton } from './widgets.js';

const SAVE_DELAY_MS = 500;

export function createPlacesView({ api, t, catalog, ai, toast, store, current = () => null, open = null }) {
  const state = { voices: [], selected: null, creating: false, timer: null };
  const side = h('aside');
  const content = h('div', { class: 'places-detail' });
  const status = h('p', { class: 'places-status muted', 'aria-live': 'polite' });
  const dialog = h('div', { class: 'notice-host' });
  const ask = h('div', { class: 'notice-host' });
  const ctx = { t, catalog, ai, toast, api, places: store };
  const nameOf = (place) => place.label || t('places.unnamed');

  // Voices that name a place, {id, name}: the saved ones, the one open in the editor as it is now.
  const users = (id) => {
    const now = current();
    const voices = state.voices.filter((v) => v.id !== now?.id);
    return places.usedBy(id, now ? [...voices, now] : voices, catalog);
  };
  const userNames = (id) => users(id).map((v) => v.name);

  const say = (text, bad = false) => { status.textContent = text; status.classList.toggle('bad', bad); };

  async function saveNow() {
    clearTimeout(state.timer);
    const result = await store.save();
    if (result.ok) say(t('places.saved'));
    else if (result.code === 'places_unfinished') say(t('places.unfinished', { name: nameOf(result.place) }), true);
    else say(t(`code.${result.code}`, {}, result.message || result.code), true);
    return result;
  }

  const later = () => {
    say(t('places.saving'));
    clearTimeout(state.timer);
    state.timer = setTimeout(saveNow, SAVE_DELAY_MS);
  };

  async function remove(place) {
    const names = userNames(place.id);
    if (names.length) {
      toast(t('places.in_use', { name: nameOf(place), voices: names.join(', ') }), true);
      return;
    }
    const yes = await confirmBar(ask, t, { message: t('places.confirm_remove', { name: nameOf(place) }),
      yes: t('places.remove'), danger: true });
    if (!yes) return;
    state.selected = selectionAfter(store.list().map((p) => p.id), place.id);
    store.remove(place.id);
    await saveNow();
  }

  // "Used by": each saved voice a link to it (the voice open in the editor and not saved yet stays plain text).
  function usedBy(place) {
    const voices = users(place.id);
    if (!voices.length) return h('p', { class: 'used-by', text: t('places.unused') });
    const saved = new Set(state.voices.map((v) => v.id));
    const names = voices.map((v, index) => [index ? ', ' : '', open && saved.has(v.id)
      ? h('a', { href: '#', class: 'used-voice', onClick: (e) => { e.preventDefault(); open(v.id); } }, v.name) : v.name]);
    return h('p', { class: 'used-by' }, t('places.used_by', { voices: '' }), names);
  }

  function card(place) {
    const draft = { label: place.label, kind: place.kind, at: { ...place.at }, area: { ...place.area }, z: place.z };
    const title = h('b', { text: nameOf(place) });
    return h('article', { class: 'card place', title: place.id, 'data-place': place.id },
      h('header', { class: 'card-head' },
        h('span', { class: 'place-icon', 'aria-hidden': 'true', text: t(`places.kind.${place.kind}.icon`) }), title,
        removeButton(t, () => remove(place), t('places.remove'))),
      usedBy(place),
      placeFields(ctx, draft, () => {
        places.setPlace(place.section, draft);
        title.textContent = nameOf(draft);
        renderList();
        later();
      }, { usedBy: () => userNames(place.id) }));
  }

  // The tab's home, with no place chosen: what a place is, a word on the list, the places recorded in game.
  function home() {
    const none = !store.list().length;
    return [h('div', { class: 'toolbar' }, h('div', { class: 'title' }, h('h2', { text: t('places.title') }),
      hint(t, 'help.ui.places', { label: t('places.title') }))),
    h('p', { class: 'help', text: t('places.help') }),
    h('p', { class: none ? 'empty' : 'muted', text: none ? t('places.empty') : t('places.pick') }),
    surveysBlock(ctx)];
  }

  function usedCount(id) {
    const n = users(id).length;
    if (!n) return t('places.used_none');
    return n === 1 ? t('places.used_one') : t('places.used_count', { n });
  }

  function renderList() {
    masterList(side, {
      title: t('places.list_title'), currentId: state.creating ? null : state.selected, itemClass: 'place-item',
      listClass: 'places-list', onOpen: select,
      entries: store.list().map((place) => ({ id: place.id, name: nameOf(place), sub: usedCount(place.id),
        lead: h('span', { class: 'place-icon', 'aria-hidden': 'true', text: t(`places.kind.${place.kind}.icon`) }),
        marks: [h('span', { class: 'sr', text: ` (${t(`places.kind.${place.kind}`)})` })] })),
      head: [add],
      foot: [button('neutral', { id: 'places-home', class: `md-action${state.selected || state.creating ? '' : ' on'}`,
        'aria-current': state.selected || state.creating ? null : 'true', onClick: () => select(null) },
      t('places.home'))],
    });
  }

  function renderDetail() {
    if (state.creating) return;
    const place = state.selected ? store.find(state.selected) : null;
    if (!place) state.selected = null;
    append(clear(content), [place ? card(place) : home()]);
  }

  function render() {
    renderList();
    renderDetail();
  }

  function select(id) {
    if (state.creating) { clear(dialog); state.creating = false; }
    state.selected = id;
    render();
    detail.scrollIntoView?.({ block: 'nearest' });
  }

  // Reads the places and every voice again (who uses what).
  async function start() {
    const loaded = await store.load();
    if (!loaded.ok) say(t(`code.${loaded.code}`, {}, loaded.message || loaded.code), true);
    const listed = await api.voices();
    const entries = (listed.voices ?? []).filter((entry) => !entry.removed);
    const read = await Promise.all(entries.map(async (entry) => [entry, await api.read(entry.id)]));
    state.voices = read.filter(([, r]) => r.ok && (r.text ?? '').trim()).map(([entry, r]) => {
      const model = sheet.parse(r.text);
      return { id: entry.id, name: sheet.value(model.head, 'name') || entry.name || entry.id, model };
    });
    // Who uses what changed: the counts of the list, the "used by" of the place shown. The home shows no voice: it is
    // left as it is (a record being added keeps its question open).
    renderList();
    if (state.selected) renderDetail();
  }

  // The form of a new place in the right pane; the place made is chosen, a cancel goes back to the one before.
  const add = button('add', { id: 'place-new', class: 'md-action', onClick: async () => {
    if (store.full()) { toast(t('places.full', { n: catalog.sheet.maxPlaces }), true); return; }
    if (state.creating) return;
    state.creating = true;
    clear(content);
    renderList();
    const id = await newPlaceDialog(ctx, dialog);
    if (!state.creating) return;              // another place chosen meanwhile
    state.creating = false;
    if (id) state.selected = id;
    render();
  } }, t('places.add'));

  const detail = h('div', {}, dialog, ask, status, content);
  const el = masterDetail({ id: 'places', label: t('tab.places'), side, detail });
  el.classList.add('places-view');
  store.onChange(() => { if (!el.hidden) render(); });
  return { el, start, stop: () => { if (state.timer) saveNow(); } };
}
