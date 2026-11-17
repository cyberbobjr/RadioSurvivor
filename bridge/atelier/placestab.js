// "Places" view (E25-T03, ADR lieux communs D02, D06-D08): the places every voice shares (personas/_places.txt), one
// card each: its name, a spot or an area, its square or its corners pasted from the map, and the voices that use it;
// a place a voice uses cannot be deleted (the voices are named). New places, from scratch or from the places recorded
// in game (surveys.js). Every change is saved by itself once the place is finished (placestore.js): there is no file
// to save by hand.
//
// createPlacesView({api, t, catalog, ai, toast, store, current}) -> {el, start, stop}; current(): the voice open in the
// editor {id, name, model} (unsaved), counted as a user of the places it names.

import { confirmBar } from './dialogs.js';
import { append, clear, h } from './dom.js';
import { hint } from './help.js';
import { newPlaceDialog, placeFields } from './placeform.js';
import * as places from './places.js';
import * as sheet from './sheet.js';
import { surveysBlock } from './surveys.js';
import { button, removeButton } from './widgets.js';

const SAVE_DELAY_MS = 500;

export function createPlacesView({ api, t, catalog, ai, toast, store, current = () => null }) {
  const state = { voices: [], fresh: null, timer: null };
  const listHost = h('div', { class: 'cards places-list' });
  const status = h('p', { class: 'places-status muted', 'aria-live': 'polite' });
  const dialog = h('div', { class: 'notice-host' });
  const ask = h('div', { class: 'notice-host' });
  const surveys = h('div', { class: 'surveys-host-tab' });
  const ctx = { t, catalog, ai, toast, api, places: store };

  // Voices that name a place: the saved ones, the one open in the editor as it is now.
  const users = (id) => {
    const open = current();
    const voices = state.voices.filter((v) => v.id !== open?.id);
    return places.usedBy(id, open ? [...voices, open] : voices, catalog).map((v) => v.name);
  };

  const say = (text, bad = false) => { status.textContent = text; status.classList.toggle('bad', bad); };

  async function saveNow() {
    clearTimeout(state.timer);
    const result = await store.save();
    if (result.ok) say(t('places.saved'));
    else if (result.code === 'places_unfinished') say(t('places.unfinished', { name: result.place.label || t('places.unnamed') }), true);
    else say(t(`code.${result.code}`, {}, result.message || result.code), true);
    return result;
  }

  const later = () => {
    say(t('places.saving'));
    clearTimeout(state.timer);
    state.timer = setTimeout(saveNow, SAVE_DELAY_MS);
  };

  async function remove(place) {
    const names = users(place.id);
    if (names.length) {
      toast(t('places.in_use', { name: place.label || t('places.unnamed'), voices: names.join(', ') }), true);
      return;
    }
    const yes = await confirmBar(ask, t, { message: t('places.confirm_remove', { name: place.label || t('places.unnamed') }),
      yes: t('places.remove'), danger: true });
    if (!yes) return;
    store.remove(place.id);
    await saveNow();
  }

  function card(place) {
    const draft = { label: place.label, kind: place.kind, at: { ...place.at }, area: { ...place.area }, z: place.z };
    const names = users(place.id);
    const title = h('b', { text: place.label || t('places.unnamed') });
    return h('article', { class: `card place${state.fresh === place.id ? ' fresh' : ''}`, title: place.id,
      'data-place': place.id },
    h('header', { class: 'card-head' },
      h('span', { class: 'place-icon', 'aria-hidden': 'true', text: t(`places.kind.${place.kind}.icon`) }), title,
      removeButton(t, () => remove(place), t('places.remove'))),
    h('p', { class: 'used-by' }, names.length ? t('places.used_by', { voices: names.join(', ') }) : t('places.unused')),
    placeFields(ctx, draft, () => {
      places.setPlace(place.section, draft);
      title.textContent = draft.label || t('places.unnamed');
      later();
    }, { usedBy: () => users(place.id) }));
  }

  function render() {
    const list = store.list();
    append(clear(listHost), [list.length ? list.map(card) : h('p', { class: 'empty', text: t('places.empty') })]);
    surveys.replaceChildren(surveysBlock(ctx));
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
    render();
  }

  store.onChange(() => { if (!el.hidden) render(); });

  const add = button('add', { id: 'place-new', onClick: async () => {
    if (store.full()) { toast(t('places.full', { n: catalog.sheet.maxPlaces }), true); return; }
    const id = await newPlaceDialog(ctx, dialog);
    if (id) { state.fresh = id; render(); }
  } }, t('places.add'));

  const el = h('section', { class: 'places-view', id: 'places', 'aria-label': t('tab.places'), hidden: true },
    h('div', { class: 'toolbar' }, h('div', { class: 'title' }, h('h2', { text: t('places.title') }),
      hint(t, 'help.ui.places', { label: t('places.title') }))),
    h('p', { class: 'help', text: t('places.help') }),
    h('div', { class: 'btns' }, add), dialog, ask, status, listHost, surveys);
  return { el, start, stop: () => { if (state.timer) saveNow(); } };
}
