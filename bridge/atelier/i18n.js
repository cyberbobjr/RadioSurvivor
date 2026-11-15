// Strings of the page (ADR atelier-voix D05): French when the browser speaks French, English otherwise. Every visible
// string comes from i18n/<lang>.json; a name from the catalogue without a translation falls back to the text given.

export const LANGUAGES = ['fr', 'en'];
export const DEFAULT_LANGUAGE = 'en';

export function pickLanguage(browserLanguage) {
  return String(browserLanguage ?? '').toLowerCase().startsWith('fr') ? 'fr' : DEFAULT_LANGUAGE;
}

// t(key, args, fallback): "{name}" replaced by args.name; a missing key gives `fallback`, else the key itself.
export function createI18n(lang, strings) {
  const t = (key, args = {}, fallback = undefined) => {
    const text = Object.prototype.hasOwnProperty.call(strings, key) ? strings[key] : (fallback ?? key);
    return String(text).replace(/\{(\w+)\}/g, (all, name) => (name in args ? String(args[name]) : all));
  };
  t.has = (key) => Object.prototype.hasOwnProperty.call(strings, key);
  t.lang = lang;
  return t;
}

export async function loadI18n(browserLanguage, fetchFn = fetch) {
  const lang = pickLanguage(browserLanguage);
  const response = await fetchFn(`i18n/${lang}.json`, { cache: 'no-store' });
  if (!response.ok) throw new Error(`i18n/${lang}.json: HTTP ${response.status}`);
  return createI18n(lang, await response.json());
}
