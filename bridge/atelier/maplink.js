// Link to the community map of Build 42 (zomboidmap.com, opened in a new tab) next to the x/y/z fields of a square.
// The site reads its view from the address: #<zoom>/<x>/<y>/f<floor>, x and y in world squares (the coordinates of
// the game), the floor optional. With a usable x and y the link opens the map centred on the square, else the whole map.
// squareEditor: the x, y, floor fields of a square with that link; a position copied on the map (user 2026-11-16,
// "7966, 11751") pasted into any of them, or read by the "Paste position" button, fills them all.

import { h } from './dom.js';
import { hint } from './help.js';
import { parseSquare } from './values.js';
import { button } from './widgets.js';

export const MAP_SITE = 'https://zomboidmap.com/';
const ZOOM = 11;   // the most detailed level of the site's own tiles: a building fills the screen

const number = (v) => (v === null || v === undefined || String(v).trim() === '' ? NaN : Number(String(v).trim()));

// Address of the map centred on the square, or null when x or y is missing, not a number or negative.
export function mapUrl(x, y, z) {
  const [sx, sy, floor] = [number(x), number(y), number(z)];
  if (!Number.isFinite(sx) || !Number.isFinite(sy) || sx < 0 || sy < 0) return null;
  const level = Number.isInteger(floor) ? `/f${floor}` : '';
  return `${MAP_SITE}#${ZOOM}/${Math.round(sx)}/${Math.round(sy)}${level}`;
}

// The link and its "?" help; `read()` gives the current {x, y, z}. Call refresh() after every change of the fields.
export function mapLink(t, read) {
  const link = h('a', { class: 'maplink', target: '_blank', rel: 'noopener noreferrer', title: t('map.title') });
  const refresh = () => {
    const { x, y, z } = read();
    const url = mapUrl(x, y, z);
    link.href = url ?? MAP_SITE;
    link.textContent = t(url ? 'map.open' : 'map.home');
  };
  refresh();
  return { el: h('span', { class: 'maplink-wrap' }, link, hint(t, 'help.map', { label: t('map.open') })), refresh };
}

const AXES = ['x', 'y', 'z'];

// The clipboard read by a button: only where the browser allows it (localhost or https), else no button.
const canReadClipboard = () => typeof navigator !== 'undefined' && typeof navigator.clipboard?.readText === 'function';

async function clipboardText() {
  try { return await navigator.clipboard.readText(); } catch { return ''; }
}

// x, y and floor fields of a square, the map link, the "Paste position" button and its tip. `at` {x, y, z} as text;
// `onChange(square)` after each change (a typed field or a pasted position); `toast(text, bad)` says when the
// clipboard holds no position; `id` goes to the box (the row's label).
export function squareEditor(t, at, onChange, { id = null, toast = () => {} } = {}) {
  const square = Object.fromEntries(AXES.map((k) => [k, at?.[k] ?? '']));
  const map = mapLink(t, () => square);
  const inputs = {};
  const write = () => { onChange({ ...square }); map.refresh(); };
  const fill = (found) => {
    for (const k of AXES) if (found[k] !== undefined) { square[k] = found[k]; inputs[k].value = found[k]; }
    write();
  };
  const coord = (key, label) => {
    inputs[key] = h('input', { type: 'number', step: 1, class: 'num', value: square[key], 'aria-label': label,
      onInput: (e) => { square[key] = e.target.value; write(); },
      onPaste: (e) => {
        const found = parseSquare(e.clipboardData?.getData('text'));
        if (!found) return;
        e.preventDefault();
        fill(found);
      } });
    return inputs[key];
  };
  const paste = canReadClipboard() && button('neutral', { class: 'paste-square', onClick: async () => {
    const found = parseSquare(await clipboardText());
    if (found) fill(found); else toast(t('map.paste_none'), true);
  } }, t('map.paste'));
  return h('div', { class: 'stack square' },
    h('div', { class: 'inline', id }, 'x', coord('x', 'x'), 'y', coord('y', 'y'), t('places.floor'),
      coord('z', t('places.floor')), map.el, paste),
    h('p', { class: 'help', text: t('map.paste_tip') }));
}
