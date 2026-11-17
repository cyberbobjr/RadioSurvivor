// E22-T08 (ADR atelier-voix D08), E25-T03 (ADR lieux communs D08): the places recorded in game ("Voice workshop: record
// this place", right click in the world, solo or admin), read through GET /api/surveys (bridge/place_surveys.py, newest
// first), listed in the Places tab. Each one can become a shared place: its square and a name suggested from what was
// recorded (container, room, building), editable before it is made. The survey file is the game's: the workshop only
// reads it.
//
// ctx = {t, api, catalog, ai, toast, places: place store}

import { inputPropose, placeDetails } from './ai.js';
import { askBar } from './dialogs.js';
import { clear, h } from './dom.js';
import { hint } from './help.js';
import { POINT } from './places.js';
import { button } from './widgets.js';

const encoder = new TextEncoder();

function capitalize(text) {
  const words = String(text ?? '').replace(/[_-]+/g, ' ').trim();
  return words ? words[0].toUpperCase() + words.slice(1) : '';
}

// Text cut to `max` UTF-8 bytes, never in the middle of a character (label= of a place: 48 bytes).
export function cutBytes(text, max = 48) {
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

const square = (at) => ({ x: String(at.x), y: String(at.y), z: String(at.z ?? 0) });
const atText = (at) => `${at.x}, ${at.y}, ${at.z}`;
const sameSquare = (place, at) => place.kind === POINT && ['x', 'y', 'z'].every((k) => String(place.at[k]).trim() === String(at[k]));

function what(t, record) {
  const parts = [];
  for (const c of record.containers ?? []) parts.push(t('surveys.container', { type: capitalize(c.type) || '?' }));
  if (record.room) parts.push(t('surveys.room', { room: capitalize(record.room) }));
  else if (record.building) parts.push(t('surveys.building'));
  return parts.join(' · ');
}

function recordItem(ctx, record, ask) {
  const { t, places } = ctx;
  const label = suggestedLabel(record, t);
  const known = places.list().some((p) => sameSquare(p, record.at));
  const add = async () => {
    const draft = { label, kind: POINT, at: square(record.at) };
    const name = await askBar(ask, t, { message: t('surveys.ask'), label: t('places.label'), value: label,
      ok: t('places.add_ok'), check: (v) => (v ? null : t('places.check.no_name')),
      propose: (input) => inputPropose({ ai: ctx.ai, t, voiceId: null, sheetText: () => '' }, 'place_label', input,
        { details: () => placeDetails(t, draft, []) }) });
    if (name === null) return;
    const { id, result } = await places.create({ ...draft, label: cutBytes(name) });
    ctx.toast?.(id ? t('places.created', { name: cutBytes(name) }) : t(`code.${result.code}`, { name: result.place?.label ?? '' }, result.message), !id);
  };
  return h('li', { class: 'survey' },
    h('div', { class: 'survey-text' },
      h('b', { text: label }), ' ', h('small', { class: 'muted at', text: atText(record.at) }),
      h('small', { class: 'muted', text: [what(t, record), t('surveys.when', { time: record.time, game: record.game,
        by: record.by || '?' })].filter(Boolean).join(' · ') })),
    known ? h('small', { class: 'muted', text: t('surveys.known') })
      : button('neutral', { class: 'survey-add', disabled: places.full(), onClick: add }, t('surveys.add')));
}

let cache = null;   // last answer, shown at once when the tab is drawn again

function draw(ctx, host, ask, answer) {
  const { t } = ctx;
  const records = answer?.records ?? [];
  clear(host).append(records.length
    ? h('ul', { class: 'surveys' }, records.map((r) => recordItem(ctx, r, ask)))
    : h('p', { class: 'muted', text: answer?.ok === false ? t('surveys.unreadable') : t('surveys.none') }));
}

// Block "Places recorded in game" of the Places tab: the list, loaded from the bridge each time it is drawn.
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
