// Paquets of a trader's stock (E24-T02: "paquet" on screen, group= in the sheet, user default 2026-11-16): items that
// share one total. The author types the paquet's name; its id (what group= and the item lines store) is made from it
// and never shown, its name shown back from the id (voice.labelOf). Its items are stock lines "<Module.Type>:<id>"
// picked in the item list. Operations on a [trade] section, pure module.

import * as sheet from './sheet.js';
import { formatGroup, formatStockItem, groupName, parseGroup, parseStockItem } from './values.js';
import { labelOf, slug } from './voice.js';

const DEFAULT_TOTAL = '1-3';

const groups = (trade) => sheet.values(trade, 'group').map(parseGroup);
const stock = (trade) => sheet.values(trade, 'item').map(parseStockItem);
const writeGroups = (trade, list) => sheet.setValues(trade, 'group', list.map(formatGroup));
const writeStock = (trade, list) => sheet.setValues(trade, 'item', list.map(formatStockItem));
const ids = (trade) => sheet.values(trade, 'group').map(groupName).filter(Boolean);

// A paquet id the game accepts, not taken by another paquet of the section.
function freeId(name, taken) {
  const base = slug(name, 'paquet');
  let id = base;
  for (let n = 2; taken.includes(id); n += 1) id = `${base}_${n}`;
  return id;
}

// [{id, label, total, kinds, items: [Module.Type]}] in the order of the sheet.
export function list(trade) {
  const lines = stock(trade);
  return groups(trade).filter((g) => g.name).map((g) => ({ id: g.name, label: labelOf(g.name), total: g.total,
    kinds: g.kinds, items: lines.filter((l) => l.amount === g.name).map((l) => l.type) }));
}

// Stock lines that are in no paquet: [{type, amount}].
export function looseItems(trade) {
  const known = ids(trade);
  return stock(trade).filter((l) => !known.includes(l.amount));
}

// Replaces the loose lines by `lines`, the lines of the paquets kept after them.
export function setLooseItems(trade, lines) {
  const known = ids(trade);
  writeStock(trade, [...lines, ...stock(trade).filter((l) => known.includes(l.amount))]);
}

export function addPaquet(trade, name) {
  const id = freeId(name, ids(trade));
  writeGroups(trade, [...groups(trade), { name: id, total: DEFAULT_TOTAL, kinds: '' }]);
  return id;
}

// New name of a paquet: a new id, its items follow. Returns the id.
export function rename(trade, id, name) {
  const next = freeId(name, ids(trade).filter((n) => n !== id));
  writeGroups(trade, groups(trade).map((g) => (g.name === id ? { ...g, name: next } : g)));
  writeStock(trade, stock(trade).map((l) => (l.amount === id ? { ...l, amount: next } : l)));
  return next;
}

// Removes a paquet and its items.
export function remove(trade, id) {
  writeGroups(trade, groups(trade).filter((g) => g.name !== id));
  writeStock(trade, stock(trade).filter((l) => l.amount !== id));
}

const update = (trade, id, change) => writeGroups(trade, groups(trade).map((g) => (g.name === id ? { ...g, ...change } : g)));
export const setTotal = (trade, id, total) => update(trade, id, { total });
export const setKinds = (trade, id, kinds) => update(trade, id, { kinds });

export function addItems(trade, id, types) {
  writeStock(trade, [...stock(trade), ...types.map((type) => ({ type, amount: id }))]);
}

export function removeItem(trade, type) {
  writeStock(trade, stock(trade).filter((l) => l.type !== type));
}

// Every item type of the stock (an item appears once: the game refuses a second line of it).
export const stockTypes = (trade) => stock(trade).map((l) => l.type);
