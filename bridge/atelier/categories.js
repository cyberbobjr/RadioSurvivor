// Item categories a sheet can name (E23-T06): the shared ones of the mod (catalog, personas/_categories.txt) and the
// sheet's own [category <id>] sections, with their item types. What a trader accepts as payment (accept=<category>) is
// only the items of a category that have a trade value (catalog.isSellable), as RS_Persona.lua resolves it. Pure module.

import * as sheet from './sheet.js';
import { parseStockItem } from './values.js';

const ownSections = (model) => sheet.sectionsOf(model, 'category');

// Ids of every category the sheet can name: the shared ones (sorted), then its own in the sheet's order.
export function categoryIds(model, catalog) {
  return [...catalog.sharedCategories(), ...ownSections(model).map((s) => s.id)];
}

// Item types of a category (an own section, else a shared category: the game refuses an own one named like a shared
// one), or null when the sheet can name no such category.
export function categoryTypes(model, catalog, id) {
  const own = ownSections(model).find((s) => s.id === id);
  if (own) return sheet.values(own, 'item').map((v) => parseStockItem(v).type).filter(Boolean);
  return catalog.categoryItems(id);
}

// Every category with its sellable items: [{id, own, sellable: [Module.Type]}], in categoryIds order.
export function acceptChoices(model, catalog) {
  const own = new Set(ownSections(model).map((s) => s.id));
  return categoryIds(model, catalog).map((id) => ({
    id, own: own.has(id), sellable: [...new Set(categoryTypes(model, catalog, id) ?? [])].filter(catalog.isSellable),
  }));
}
