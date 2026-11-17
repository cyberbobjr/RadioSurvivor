// Editing a shared place and choosing one (E25-T03, ADR lieux communs D05, D07, D08): the form of a place (its name
// with the AI's "Suggest", a spot or an area as cards, the square pasted from the map, or the two corners of an area
// and its floor), and the lists of a voice: a list of places with "New place…" (placeSelect) and check boxes of places
// with a "New place…" button (placeChecks). "New place…" opens the form in the page, without leaving the voice, and the
// place is saved in the shared file at once (placestore.js). Where a point is needed (dead drop, meeting point, route,
// cache: D05) only points are offered and made.
//
// ctx = {t, catalog, ai, toast, places: place store, voiceName?: the voice that names the place (AI context)}

import { inputPropose, placeDetails } from './ai.js';
import { append, clear, h, select } from './dom.js';
import { hint } from './help.js';
import { squareEditor } from './maplink.js';
import { POINT, ZONE, PLACE_KINDS, problems } from './places.js';
import { button, cards, countedInput, numberInput, row } from './widgets.js';

export const NEW_PLACE = '__new_place__';
const LABEL_MAX = 48;

// The AI's context of a place name: no voice sheet (a place is shared), where it is and the voices using it.
const aiContext = (ctx) => ({ ai: ctx.ai, t: ctx.t, voiceId: null, sheetText: () => '' });

// A blank place of a kind.
export const blankPlace = (kind = POINT) => ({ label: '', kind, at: { x: '', y: '', z: '0' },
  area: { x1: '', y1: '', x2: '', y2: '' }, z: '0' });

// The fields of `draft` ({label, kind, at, area, z}, changed in place); `onChange()` after each change. `points`:
// only a spot may be made here. `usedBy()`: names of the voices that use it (AI context).
export function placeFields(ctx, draft, onChange, { points = false, usedBy = () => [] } = {}) {
  const { t } = ctx;
  const host = h('div', { class: 'stack place-fields' });
  const warn = h('p', { class: 'warnline', 'aria-live': 'polite' });
  const refresh = () => {
    warn.textContent = problems({ ...draft, label: draft.label ?? '' }, ctx.catalog).map((k) => t(k)).join(' ');
  };
  const changed = () => { refresh(); onChange(); };
  const name = countedInput(null, draft.label, LABEL_MAX, (v) => { draft.label = v; changed(); });
  name.input.classList.add('place-name');
  const propose = inputPropose(aiContext(ctx), 'place_label', name.input,
    { details: () => placeDetails(t, draft, usedBy()) });
  const draw = () => {
    const kinds = PLACE_KINDS.map((k) => ({ value: k, label: t(`places.kind.${k}`), help: t(`places.kind.${k}.help`),
      icon: t(`places.kind.${k}.icon`) }));
    const corner = (prefix, id) => squareEditor(t, { x: draft.area[`${prefix === 'a' ? 'x1' : 'x2'}`],
      y: draft.area[`${prefix === 'a' ? 'y1' : 'y2'}`] }, (square) => {
      const [kx, ky] = prefix === 'a' ? ['x1', 'y1'] : ['x2', 'y2'];
      draft.area[kx] = square.x;
      draft.area[ky] = square.y;
      changed();
    }, { id, toast: ctx.toast, floor: false });
    append(clear(host), [
      row(t('places.label'), (id) => h('div', { class: 'inline grow' }, Object.assign(name.input, { id }), name.counter,
        propose), t('places.label_help'), hint(t, 'help.place.label', { label: t('places.label') })),
      points ? h('p', { class: 'help', text: t('places.points_only') })
        : row(t('places.kind'), (id) => cards(`place-kind-${id}`, kinds, draft.kind, (v) => {
          draft.kind = v;
          changed();
          draw();
        }, { id, class: 'place-kind' }), null, hint(t, 'help.place.kind', { label: t('places.kind') })),
      draft.kind === ZONE
        ? [row(t('places.corner_a'), (id) => corner('a', id), t('places.corner_help'),
          hint(t, 'help.place.area', { label: t('places.corner_a') })),
        row(t('places.corner_b'), (id) => corner('b', id), null),
        row(t('places.floor_row'), (id) => numberInput(draft.z, (v) => { draft.z = v; changed(); },
          { id, min: -32, max: 31, step: 1, class: 'num place-floor' }), t('places.floor_help'))]
        : row(t('places.at'), (id) => squareEditor(t, draft.at, (square) => { draft.at = square; changed(); },
          { id, toast: ctx.toast }), t('places.at_help'), hint(t, 'help.place.at', { label: t('places.at') })),
      warn]);
    refresh();
  };
  draw();
  return host;
}

// The form of a new place in `host`; resolves to its id once saved in the shared file, null when cancelled.
export function newPlaceDialog(ctx, host, { points = false } = {}) {
  const { t } = ctx;
  return new Promise((resolve) => {
    const draft = blankPlace(POINT);
    const done = (id) => { clear(host); resolve(id); };
    const error = h('p', { class: 'warnline', 'aria-live': 'polite' });
    const create = async () => {
      const open = problems(draft, ctx.catalog);
      if (open.length) { error.textContent = open.map((k) => t(k)).join(' '); return; }
      const { id, result } = await ctx.places.create({ ...draft, label: draft.label.trim() });
      if (!id) { error.textContent = t(`code.${result.code}`, { name: result.place?.label ?? '' }, result.message || result.code); return; }
      ctx.toast?.(t('places.created', { name: draft.label.trim() }));
      done(id);
    };
    clear(host).append(h('div', { class: 'notice new-place', role: 'dialog', 'aria-label': t('places.new_title') },
      h('h4', { text: t('places.new_title') }),
      h('p', { class: 'help', text: t('places.new_help') }),
      placeFields(ctx, draft, () => { error.textContent = ''; }, { points,
        usedBy: () => (ctx.voiceName ? [ctx.voiceName] : []) }),
      error,
      h('div', { class: 'btns' },
        button('neutral', { onClick: () => done(null) }, ctx.t('dialog.cancel')),
        button('primary', { class: 'place-create', onClick: create }, t('places.create')))));
    host.querySelector('input')?.focus();
  });
}

const placeOptions = (ctx, points) => ctx.places.choices({ points })
  .map((c) => ({ value: c.value, label: points ? c.label : `${ctx.t(`places.kind.${c.kind}.icon`)} ${c.label}` }));

// A list of shared places (`points`: points only) with `extra` choices first (the distances of an objective) and
// "New place…" last; `onChange(value)` with the id of a place made from it.
export function placeSelect(ctx, value, onChange, { points = false, extra = [], empty = null, id = null } = {}) {
  const { t } = ctx;
  const dialog = h('div', { class: 'notice-host' });
  const options = [...(empty === null ? [] : [{ value: '', label: empty }]), ...extra, ...placeOptions(ctx, points),
    { value: NEW_PLACE, label: t('places.new_option') }];
  const list = select(options, value ?? '', async (v) => {
    if (v !== NEW_PLACE) { onChange(v); return; }
    list.value = value ?? '';
    const created = await newPlaceDialog(ctx, dialog, { points });
    if (created) onChange(created);
  }, { id, class: 'place-select' });
  return h('div', { class: 'stack' }, list, dialog);
}

// Check boxes of shared places (`points`: points only), `selected` a list of ids, and a "New place…" button that ticks
// the place it makes.
export function placeChecks(ctx, selected, onChange, { points = false, id = null } = {}) {
  const { t } = ctx;
  const chosen = [...selected];
  const dialog = h('div', { class: 'notice-host' });
  const options = placeOptions(ctx, points);
  const boxes = h('div', { class: 'checks chips place-checks', id },
    options.map((o) => h('label', { class: 'check', 'data-value': o.value },
      h('input', { type: 'checkbox', checked: chosen.includes(o.value), onChange: (e) => {
        const at = chosen.indexOf(o.value);
        if (e.target.checked && at < 0) chosen.push(o.value);
        if (!e.target.checked && at >= 0) chosen.splice(at, 1);
        onChange([...chosen]);
      } }), h('span', {}, h('b', { text: o.label })))));
  return h('div', { class: 'stack' },
    options.length ? boxes : h('p', { class: 'muted', id, text: t('places.none_yet') }),
    h('div', {}, button('add', { class: 'place-new', onClick: async () => {
      const created = await newPlaceDialog(ctx, dialog, { points });
      if (created) onChange([...chosen, created]);
    } }, t('places.new_option'))),
    dialog);
}
