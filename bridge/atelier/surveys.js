// E22-T08 (ADR atelier-voix D08): the places recorded in game ("Voice workshop: record this place", right click in
// the world, solo or admin), read through GET /api/surveys (bridge/place_surveys.py, newest first). Each one can become
// a place of the voice: its square, a name suggested from what was recorded (container, room, building) and uses
// suggested the same way (container: dead drop; building: job place and map mark), all editable in the place's card.
// The survey file is the game's: the workshop only reads it.

import { inputPropose, placeDetails } from './ai.js';
import { askBar } from './dialogs.js';
import { clear, h } from './dom.js';
import { hint } from './help.js';
import * as voice from './voice.js';
import { button } from './widgets.js';

const LABEL_BYTES = 48;   // [place] label= limit (persona-format.md), counted in UTF-8 bytes
const encoder = new TextEncoder();

function capitalize(text) {
  const words = String(text ?? '').replace(/[_-]+/g, ' ').trim();
  return words ? words[0].toUpperCase() + words.slice(1) : '';
}

// Text cut to `max` UTF-8 bytes, never in the middle of a character.
export function cutBytes(text, max = LABEL_BYTES) {
  let out = '';
  for (const char of String(text ?? '')) {
    if (encoder.encode(out + char).length > max) break;
    out += char;
  }
  return out;
}

// Name suggested for a record: its first container (and room), else its room, else its building, else outdoors.
export function suggestedLabel(record, t) {
  const container = record.containers?.[0];
  const room = capitalize(record.room);
  let label;
  if (container?.type) label = room ? `${capitalize(container.type)} - ${room}` : capitalize(container.type);
  else if (room) label = room;
  else if (record.building) label = t('surveys.building');
  else label = t('surveys.outdoors');
  return cutBytes(label);
}

// Uses suggested for a record: a container is a dead drop; a building, a job place and a map mark; else a map mark.
export function suggestedUses(record) {
  if (record.containers?.length) return ['drop'];
  if (record.room || record.building) return ['target', 'mark'];
  return ['mark'];
}

const atText = (at) => `${at.x}, ${at.y}, ${at.z}`;
const sameSquare = (place, at) => ['x', 'y', 'z'].every((k) => String(place.at[k]).trim() === String(at[k]));

function what(t, record) {
  const parts = [];
  for (const c of record.containers ?? []) parts.push(t('surveys.container', { type: capitalize(c.type) || '?' }));
  if (record.room) parts.push(t('surveys.room', { room: capitalize(record.room) }));
  else if (record.building) parts.push(t('surveys.building'));
  return parts.join(' · ');
}

function recordItem(ctx, record, ask, full) {
  const { model, t } = ctx;
  const label = suggestedLabel(record, t);
  const known = voice.places(model).some((p) => sameSquare(p, record.at));
  const add = async () => {
    const name = await askBar(ask, t, { message: t('surveys.ask'), label: t('places.label'), value: label,
      ok: t('places.add_ok'), check: (v) => (v ? null : t('places.ask')),
      propose: (input) => inputPropose(ctx, 'place_label', input,
        { details: () => placeDetails(t, suggestedUses(record), record.at) }) });
    if (name === null) return;
    voice.addPlace(model, { label: cutBytes(name), at: { ...record.at }, uses: suggestedUses(record) });
    ctx.ui.open_place = true;
    ctx.changed();
    ctx.rerender();
  };
  return h('li', { class: 'survey' },
    h('div', { class: 'survey-text' },
      h('b', { text: label }), ' ', h('small', { class: 'muted at', text: atText(record.at) }),
      h('small', { class: 'muted', text: [what(t, record), t('surveys.when', { time: record.time, game: record.game,
        by: record.by || '?' })].filter(Boolean).join(' · ') })),
    known ? h('small', { class: 'muted', text: t('surveys.known') })
      : button('neutral', { class: 'survey-add', disabled: full, onClick: add }, t('surveys.add')));
}

let cache = null;   // last answer, shown at once when the step is drawn again

function draw(ctx, host, ask, answer) {
  const { t } = ctx;
  const records = answer?.records ?? [];
  const max = ctx.catalog.sheet.maxPlaces;
  const full = Boolean(max && voice.places(ctx.model).length >= max);
  clear(host).append(records.length
    ? h('ul', { class: 'surveys' }, records.map((r) => recordItem(ctx, r, ask, full)))
    : h('p', { class: 'muted', text: answer?.ok === false ? t('surveys.unreadable') : t('surveys.none') }));
}

// Block "Places recorded in game" of the places panel: the list, loaded from the bridge each time it is drawn.
export function surveysBlock(ctx) {
  const { t } = ctx;
  const host = h('div', { class: 'surveys-host' });
  const ask = h('div', { class: 'notice-host' });
  if (cache) draw(ctx, host, ask, cache);
  ctx.api?.surveys().then((answer) => {
    if (answer.ok) cache = answer;
    draw(ctx, host, ask, cache ?? answer);
  });
  return h('section', { class: 'surveys-block' },
    h('h4', {}, t('surveys.title'), ' ', hint(t, 'help.ui.surveys', { label: t('surveys.title') })),
    h('p', { class: 'help', text: t('surveys.help') }),
    ask, host);
}
