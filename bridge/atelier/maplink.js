// Link to the community map of Build 42 (zomboidmap.com, opened in a new tab) next to the x/y/z fields of a square.
// The site reads its view from the address: #<zoom>/<x>/<y>/f<floor>, x and y in world squares (the coordinates of
// the game), the floor optional. With a usable x and y the link opens the map centred on the square, else the whole map.

import { h } from './dom.js';
import { hint } from './help.js';

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
