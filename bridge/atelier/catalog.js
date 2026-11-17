// Catalogue of the workshop (bridge/atelier/catalog.json, generated from the mod by tools/gen_atelier_catalog.py, ADR
// D03): every choice the page offers comes from here, never from a list written in the page. A mission type or a
// reward kind added to the mod appears in the page by regenerating the catalogue only.

import { createItemIndex } from './items.js';
import { sheetFrequency } from './values.js';

const sorted = (list) => [...list].sort();

export function createCatalog(data) {
  const header = data.header ?? {};
  const sections = data.sections ?? {};
  const missionTypes = data.missionTypes ?? {};
  const rewardKinds = data.rewardKinds ?? {};
  const voices = data.voices ?? {};
  const radioLevels = data.radioLevels ?? [];
  const stepKhz = data.radioStepKhz ?? 200;
  const levelOf = (khz) => radioLevels.find((l) => khz >= l.minKhz && khz <= l.maxKhz)?.id ?? null;
  // Mission type: its parameters ({key: kind}), voice set-ups (aimAt, dropAccepts...) and English description.
  const missionType = (name) => (missionTypes[name] ? {
    name, params: missionTypes[name].params ?? {}, setups: missionTypes[name].setups ?? [],
    voiceText: missionTypes[name].voiceText ?? '',
  } : null);
  // Reward kind and the kind of its parameter (null: none).
  const rewardKind = (name) => (rewardKinds[name] ? { name, param: rewardKinds[name].param ?? null } : null);
  // Item types a trader can sell (a sale value in CA_TradeValues, E22-T17): RS_Trade refuses every other one.
  const sellable = new Set(data.sellable ?? []);
  let itemIndex = null;
  let sellableIndex = null;

  return {
    data,
    sheet: data.sheet ?? { format: '1', separator: '[prompt]' },

    missionTypes: () => sorted(Object.keys(missionTypes)).map(missionType),
    missionType,
    rewardKinds: () => sorted(Object.keys(rewardKinds)).map(rewardKind),
    rewardKind,

    paramKinds: () => data.paramKinds ?? [],
    skills: () => data.skills ?? [],
    sharedCategories: () => sorted(Object.keys(data.categories ?? {})),
    // Item types of a shared category (personas/_categories.txt), or null when there is no such shared category.
    categoryItems: (id) => (data.categories ?? {})[id]?.items?.map((item) => item.type) ?? null,
    // Every item type of the game and of the mod with its category, searchable by name (items.js), built on first use.
    itemIndex: () => { itemIndex ??= createItemIndex(data.items ?? {}, data.itemCategories ?? {}); return itemIndex; },
    // The same, limited to the items a trader can sell: what the trader's stock offers.
    sellableItemIndex: () => {
      sellableIndex ??= createItemIndex(Object.fromEntries(Object.entries(data.items ?? {}).filter(([type]) => sellable.has(type))),
        data.itemCategories ?? {});
      return sellableIndex;
    },
    isSellable: (type) => sellable.has(type),
    // Names of the game's loot lists offered for a [note] key (loot, glovebox).
    lootLists: (key) => (data.lootLists ?? {})[key] ?? [],

    // Head of a sheet: keys, required, closed choices (actions, radio, state, location).
    header: () => ({
      keys: header.keys ?? [], required: header.required ?? [],
      choices: header.choices ?? {}, budgetPrefix: header.budgetPrefix ?? 'budget.',
    }),
    headerChoices: (key) => (header.choices ?? {})[key] ?? null,

    // Grammar of a section kind: keys, required, repeatable, closed choices, id or not.
    section: (kind) => {
      const s = sections[kind];
      return s ? {
        kind, keys: s.keys ?? [], required: s.required ?? [], repeatable: s.repeatable ?? [],
        choices: s.choices ?? {}, hasId: Boolean(s.hasId), rank: s.rank ?? 99,
      } : null;
    },
    sectionKinds: () => Object.keys(sections),
    placeUses: () => (sections.place?.choices?.use) ?? [],
    arrivals: () => (sections.trade?.choices?.arrival) ?? [],

    // Radio a voice needs (E24-T01, RS_RadioLevels of the mod): [{id, minKhz, maxKhz, zones}], weakest first. The
    // first one is the default of a new voice: everybody hears it.
    radioLevels: () => radioLevels,
    // Weakest radio level that tunes `khz` (the radio a fixed frequency needs), or null outside every radio.
    levelOf,
    // Radio a fixed frequency written in a sheet (frequency=, MHz) needs: null when it is not on the grid of the
    // radios or outside every radio (the badge of the step "where", the dashboard).
    frequencyLevel: (text) => {
      const khz = sheetFrequency(text);
      return khz !== null && khz % stepKhz === 0 ? levelOf(khz) : null;
    },
    // Frequencies every radio tunes (kHz), on the step of the radios.
    frequencyBounds: () => ({
      min: Math.min(...radioLevels.map((l) => l.minKhz)), max: Math.max(...radioLevels.map((l) => l.maxKhz)),
      step: stepKhz,
    }),
    // Shipped voices with a fixed frequency: [{id, name, khz}], `exceptId` left out (the voice being edited).
    fixedFrequencies: (exceptId = null) => sorted(Object.keys(voices))
      .filter((id) => id !== exceptId && Number.isFinite(voices[id].frequencyKhz))
      .map((id) => ({ id, name: voices[id].name ?? id, khz: voices[id].frequencyKhz })),
    voiceIds: () => sorted(Object.keys(voices)),
  };
}

export async function loadCatalog(fetchFn = fetch, url = 'catalog.json') {
  const response = await fetchFn(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`catalog.json: HTTP ${response.status}`);
  return createCatalog(await response.json());
}
