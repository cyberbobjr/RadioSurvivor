// Step 3, personality: what the voice can do (action cards, "Talk" always on), the voices she may pass on, the language
// her personality is written in (language=, E24-T02 user decision: English by default, French allowed, the AI that
// plays her reads both; the text is kept as written) and the personality text itself ([prompt], the only place of her
// character and past), which the bridge's AI can write from a few sentences (E22-T06, ai.js). E27-T02: the recipe help
// block ([help], recipehelpform.js) after the actions: the jobs she knows, from which reputation and when she answers.

import { personalityPanel } from '../ai.js';
import { h } from '../dom.js';
import { hint } from '../help.js';
import { recipeHelpBlock } from '../recipehelpform.js';
import * as sheet from '../sheet.js';
import * as story from '../story.js';
import { formatList, parseList } from '../values.js';
import { PROMPT_LANGUAGES, starterPrompt } from '../voice.js';
import { cards, checkboxes, choice, row } from '../widgets.js';

// Head key an action brings with it: shown only while the action is allowed.
const ACTION_KEYS = { share_frequency: 'shares' };
// Action every voice has: shown ticked and locked.
const ALWAYS = 'say';
// Actions not offered as cards: the game refuses them in a sheet for now (signal, place_scene), keeps them to the
// notebook's own missions (place_cache) or gives them with start_mission (report_mission). A sheet that names one keeps it.
const NOT_OFFERED = new Set(['signal', 'place_scene', 'place_cache', 'report_mission']);
const DEFAULT_LANGUAGE = 'en';

// Language of the personality text: a card per language; an untouched starter text follows the language picked.
function languageCards({ model, t, changed, rerender }, id) {
  const head = model.head;
  const current = sheet.value(head, 'language') ?? DEFAULT_LANGUAGE;
  const options = PROMPT_LANGUAGES.map((lang) => ({ value: lang, label: t(`personality.lang.${lang}`),
    help: t(`personality.lang.${lang}.help`), icon: t(`personality.lang.${lang}.icon`) }));
  return cards('prompt-language', options, current, (lang) => {
    const name = sheet.value(head, 'name') ?? '';
    if (sheet.promptText(model).trim() === starterPrompt(name, current).trim()) sheet.setPromptText(model, starterPrompt(name, lang));
    sheet.setValue(head, 'language', lang);
    changed();
    rerender();
  }, { id, class: 'compact' });
}

export default {
  id: 'personality',
  fields: ['actions', 'shares', 'budget', 'language'],
  blocks: ['prompt', 'help'],
  render(ctx) {
    const { model, catalog, t, voiceId, voices, ai, changed, rerender } = ctx;
    const head = model.head;
    const language = sheet.value(head, 'language') ?? DEFAULT_LANGUAGE;
    const writer = personalityPanel({ ai, t, voiceId, name: sheet.value(head, 'name') ?? '',
      description: sheet.description(model), sheetText: ctx.sheetText,
      currentPrompt: () => sheet.promptText(model),
      // the story lines of the missions (story.js) stay: the AI does not know them
      usePrompt: (text) => { sheet.setPromptText(model, story.carry(sheet.promptText(model), text)); changed(); rerender(); } });
    const actions = parseList(sheet.value(head, 'actions') ?? ALWAYS);
    const options = (catalog.headerChoices('actions') ?? []).filter((v) => !NOT_OFFERED.has(v))
      .map((v) => ({ ...choice(t, 'action', v), label: `${t(`action.${v}.icon`)} ${t(`action.${v}`)}`, locked: v === ALWAYS,
        hint: hint(t, `help.head.actions.${v}`, { label: t(`action.${v}`) }) }));
    const others = voices.filter((v) => v.id !== voiceId && !v.removed)
      .map((v) => ({ value: v.id, label: v.name || v.id }));
    const extras = Object.entries(ACTION_KEYS).filter(([action]) => actions.includes(action)).map(([action, key]) =>
      row(t(`personality.${key}`), () => checkboxes(others, parseList(sheet.value(head, key)), (list) => {
        sheet.setValue(head, key, formatList(list));
        changed();
      }, { class: 'checks cols' }), t(`personality.${key}_help`, {}, t(`action.${action}.help`)),
      hint(t, `help.head.${key}`, { label: t(`personality.${key}`) })));
    return h('div', { class: 'form' },
      row(t('personality.actions'), () => checkboxes(options, actions, (list) => {
        sheet.setValue(head, 'actions', formatList([ALWAYS, ...list.filter((a) => a !== ALWAYS)]));
        changed();
        rerender();
      }, { class: 'checks cols action-cards' }), t('personality.actions_help'),
      hint(t, 'help.head.actions', { label: t('personality.actions') })),
      extras,
      recipeHelpBlock(ctx),
      row(t('personality.language'), (id) => languageCards(ctx, id), t('personality.language_help'),
        hint(t, 'help.head.language', { label: t('personality.language') })),
      row(t('personality.prompt'), (id) => h('div', { class: 'stack' },
        h('div', { class: 'inline' }, writer.button,
          !ai.available && h('small', { class: 'muted', text: t('ai.unavailable_short') })),
        writer.panel,
        h('textarea', { id, class: 'prompt', rows: 14, spellcheck: 'true', lang: language, value: sheet.promptText(model),
          onInput: (e) => { sheet.setPromptText(model, e.target.value); changed(); } })),
      t('personality.prompt_help'), hint(t, 'help.ui.prompt', { label: t('personality.prompt') })));
  },
};
