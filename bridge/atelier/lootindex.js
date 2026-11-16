// Loot lists of the game as a pick-list (E24-T03, charter rule 7: no list name is ever typed). Pure module with the
// same contract as the item index (items.js) that the browser reads (itembrowser.js): find(query, lang, {category,
// limit}) -> {items: [{type, name, cat, catName}], total}, categories(lang) -> [{value, label}], get(type, lang).
// `type` is the game's list name (what the sheet stores, tooltip only), `name` the list in words ("Medical office
// desk"), `cat` its kind: home furniture, offices and public services, shops, crates and storage, vehicles, other.
// The kinds are data (LOOT_KINDS, first match wins), not a chain of ifs.

import { fold } from './items.js';

const MAX_RESULTS = 200;

// kind -> pattern on the game's list name, in the order they are tried.
export const LOOT_KINDS = [
  ['vehicle', /GloveBox|Trunk/],
  ['home', /Home|^(Bedroom|Kitchen|LivingRoom|Bathroom|Garage|Closet|Wardrobe|Dresser|Laundry|Fridge|Freezer|Stove|Safehouse|Motel|Derelict|Dish)/],
  ['office', /Office|Desk|Filing|Police|School|Classroom|University|Library|Hospital|Medical|Post|Bank|Daycare|Prison|Mayor|Morgue|Laborator|Fire/],
  ['shop', /Store|Shop|Gigamart|Grocery|Counter|Clothing|Bakery|Butcher|Liquor|Spiffos|Jays|Pizza|Burger|Bar|Cafe|Restaurant|Serving|Produce|Sport|Gun|Electronic|Jewelry|Pawn|Magazine|Music|Camping|Fishing|Comic|Tobacco|Diner/],
  ['storage', /^Crate|Storage|Locker|Bin|Shelves|Shelf/],
];
const OTHER = 'other';

// A loot list of the game in words: "MedicalOfficeDesk" -> "Medical office desk" (charter rule 1: the game's name only
// in the tooltip).
export function lootLabel(name) {
  const words = String(name ?? '').replace(/_/g, ' ').replace(/([a-z0-9])([A-Z])/g, '$1 $2').trim().toLowerCase();
  return words ? words[0].toUpperCase() + words.slice(1) : '';
}

export function lootKind(name) {
  return (LOOT_KINDS.find(([, pattern]) => pattern.test(name)) ?? [OTHER])[0];
}

// `names` the game's list names, `kindName(kind, lang)` the kind in words.
export function createLootIndex(names, kindName) {
  const entries = [...new Set(names)].filter(Boolean).map((type) => {
    const name = lootLabel(type);
    return { type, name, cat: lootKind(type), key: fold(`${name} ${type}`) };
  }).sort((a, b) => a.name.localeCompare(b.name));
  const byType = new Map(entries.map((e) => [e.type, e]));
  const view = (e, lang) => ({ type: e.type, name: e.name, cat: e.cat, catName: kindName(e.cat, lang) });

  const find = (query, lang, { category = '', limit = MAX_RESULTS } = {}) => {
    const words = fold(query).split(/\s+/).filter(Boolean);
    const found = entries.filter((e) => (!category || e.cat === category) && words.every((w) => e.key.includes(w)));
    return { items: found.slice(0, limit).map((e) => view(e, lang)), total: found.length };
  };

  return {
    size: entries.length,
    get: (type, lang) => (byType.has(type) ? view(byType.get(type), lang) : null),
    find,
    categories: (lang) => [...new Set(entries.map((e) => e.cat))]
      .map((cat) => ({ value: cat, label: kindName(cat, lang) }))
      .sort((a, b) => a.label.localeCompare(b.label, lang)),
  };
}
