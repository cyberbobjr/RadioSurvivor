// Item types of the game for the item fields (E22-T12): catalog.items {'Module.Type': {en, fr, kg, cat}} generated from
// the game's scripts and names (tools/game_items.py), catalog.itemCategories {cat: {en, fr}} the names the game's
// inventory gives the categories. Pure module: search by name in the page's language (accents and case ignored), by the
// other language's name or by the type itself, within one category or all; the sheet always stores Module.Type.

const MAX_RESULTS = 12;

// "Pansements adhésifs" -> "pansements adhesifs".
export function fold(text) {
  return String(text ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
}

export function createItemIndex(items = {}, categories = {}) {
  const catName = (cat, lang) => (cat ? (categories[cat]?.[lang] ?? categories[cat]?.en ?? cat) : '');
  const entries = Object.entries(items).map(([type, item]) => ({
    type, en: item.en ?? type, fr: item.fr ?? item.en ?? type, kg: item.kg ?? null, cat: item.cat ?? '',
    keys: { en: fold(item.en), fr: fold(item.fr ?? item.en), type: fold(type) },
  }));
  const byType = new Map(entries.map((e) => [e.type, e]));
  const nameOf = (e, lang) => (lang === 'fr' ? e.fr : e.en);
  const view = (e, lang) => ({ type: e.type, name: nameOf(e, lang), kg: e.kg, cat: e.cat, catName: catName(e.cat, lang) });

  // Rank of an entry for the query words (lower is better), or null when a word matches nowhere: the page language's
  // name first (starting with the query, then a word of it starting with it, then anywhere), then the other language,
  // then the type.
  const rank = (e, words, lang) => {
    const other = lang === 'fr' ? 'en' : 'fr';
    const fields = [e.keys[lang], e.keys[other], e.keys.type];
    let worst = 0;
    for (const word of words) {
      let best = null;
      fields.forEach((text, index) => {
        const at = text.indexOf(word);
        if (at < 0) return;
        const where = at === 0 ? 0 : (/[\s\-.(/]/.test(text[at - 1]) ? 1 : 2);
        const score = index * 3 + where;
        if (best === null || score < best) best = score;
      });
      if (best === null) return null;
      worst = Math.max(worst, best);
    }
    return worst;
  };
  const byName = (lang) => (a, b) => (a.e.keys[lang] < b.e.keys[lang] ? -1 : a.e.keys[lang] > b.e.keys[lang] ? 1
    : a.e.type.localeCompare(b.e.type));

  // Matches of `query` in `category` ('' = all): {items: [{type, name, kg, cat, catName}] (at most `limit`), total}.
  // An empty query lists the whole category by name.
  const find = (query, lang, { category = '', limit = MAX_RESULTS } = {}) => {
    const words = fold(query).split(/\s+/).filter(Boolean);
    const found = [];
    for (const e of entries) {
      if (category && e.cat !== category) continue;
      const score = words.length ? rank(e, words, lang) : 0;
      if (score !== null) found.push({ e, score, name: nameOf(e, lang) });
    }
    const named = byName(lang);
    found.sort((a, b) => a.score - b.score || (words.length ? a.name.length - b.name.length : 0) || named(a, b));
    return { items: found.slice(0, limit).map((f) => view(f.e, lang)), total: found.length };
  };

  return {
    size: entries.length,
    // {type, name, kg, cat, catName} of a type in `lang`, or null when the game has no such item.
    get: (type, lang) => (byType.has(type) ? view(byType.get(type), lang) : null),
    // Best matches of `query` (not empty) in all categories: [{type, name, kg, cat, catName}], at most `limit`.
    search: (query, lang, limit = MAX_RESULTS) => (fold(query) ? find(query, lang, { limit }).items : []),
    find,
    // Categories used by the items, [{value, label}] sorted by their name in `lang`.
    categories: (lang) => [...new Set(entries.map((e) => e.cat).filter(Boolean))]
      .map((cat) => ({ value: cat, label: catName(cat, lang) }))
      .sort((a, b) => a.label.localeCompare(b.label, lang) || a.value.localeCompare(b.value)),
  };
}

// "0.1 kg" in the page's language ("0,1 kg" in French).
export function formatKg(kg, lang) {
  if (kg === null || kg === undefined) return '';
  return `${Number(kg).toLocaleString(lang === 'fr' ? 'fr-FR' : 'en-US', { maximumFractionDigits: 2 })} kg`;
}
