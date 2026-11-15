// Step 4, missions: the places of the voice ([place]: name, x y z, uses) and her missions ([mission]). Every mission
// form is generated from the catalogue: its type's parameters (field by kind), its voice set-ups (target place, dead
// drops) and the [mission] keys. A mission type added to the mod shows up here without any change.

import { suggestButton } from '../ai.js';
import { askBar } from '../dialogs.js';
import { h, select } from '../dom.js';
import { field, fieldOptions } from '../fields.js';
import { choiceTopics, hint, selectHelp, withHint } from '../help.js';
import * as sheet from '../sheet.js';
import { surveysBlock } from '../surveys.js';
import { formatList, parseList } from '../values.js';
import * as voice from '../voice.js';
import { button, chanceChoice, checkboxes, choice, fold, removeButton, row, textInput } from '../widgets.js';

const typeTitle = (t, type) => t(`mission.${type.name}`, {}, type.name);
const typeHelp = (t, type) => t(`mission.${type.name}.help`, {}, type.voiceText);
const paramLabel = (t, key) => t(`param.${key}`, {}, key);
// Help of a parameter: of this type, else of the parameter name, else of its kind (help.js picks the first found).
const paramTopics = (type, key, kind) => [`help.mission_type.${type.name}.${key}`, `help.param.${key}`, `help.param_kind.${kind}`];
// "?" of a mission type: what it is, what the player does, and its own settings.
const typeHint = (t, type) => hint(t, `help.mission_type.${type.name}`, { label: typeTitle(t, type),
  choicesTitle: t('hint.settings'),
  choices: Object.entries(type.params).map(([key, kind]) => ({ label: paramLabel(t, key), topic: paramTopics(type, key, kind) })) });

// Set-up of a mission type -> the [mission] key it reads (shown only for the types that declare it).
const SETUP_FIELDS = {
  aimAt: (ctx, mission, opts) => row(`${ctx.t('mission.target')} ${ctx.t('field.required')}`,
    (id) => select([{ value: '', label: ctx.t('field.choose') }, ...opts.places], sheet.value(mission, 'target') ?? '',
      (v) => { sheet.setValue(mission, 'target', v); ctx.changed(); }, { id }), ctx.t('mission.target_help'),
    hint(ctx.t, 'help.mission.target', { label: ctx.t('mission.target') })),
  dropAccepts: (ctx, mission, opts) => row(ctx.t('mission.drops'), () => (opts.drops.length
    ? checkboxes(opts.drops, parseList(sheet.value(mission, 'drops')), (list) => {
      sheet.setValue(mission, 'drops', formatList(list));
      ctx.changed();
    }) : h('p', { class: 'warnline', text: ctx.t('mission.no_drop') })), ctx.t('mission.drops_help'),
  hint(ctx.t, 'help.mission.drops', { label: ctx.t('mission.drops') })),
};

function placeCard(ctx, place, index) {
  const { catalog, t, changed, rerender, model } = ctx;
  const at = { ...place.at };
  const uses = catalog.placeUses().map((u) => withHint(t, 'help.place.use', choice(t, 'use', u)));
  const coord = (key) => h('input', { type: 'number', step: 1, class: 'num', value: at[key], 'aria-label': key,
    onInput: (e) => { at[key] = e.target.value; voice.setPlace(place.section, { at }); changed(); } });
  return h('article', { class: 'card' },
    h('header', { class: 'card-head' },
      h('b', { text: place.label || t('places.unnamed', { n: index + 1 }) }),
      h('code', { text: place.id }),
      removeButton(t, () => { sheet.removeSection(model, place.section); changed(); rerender(); }, t('places.remove'))),
    row(t('places.label'), (id) => textInput(id, place.label, (v) => {
      voice.setPlace(place.section, { label: v });
      changed();
    }, { maxlength: 48 }), t('places.label_help'), hint(t, 'help.place.label', { label: t('places.label') })),
    row(t('places.at'), (id) => h('div', { class: 'inline', id }, 'x', coord('x'), 'y', coord('y'), 'z', coord('z')),
      t('places.at_help'), hint(t, 'help.place.at', { label: t('places.at') })),
    row(t('places.uses'), () => checkboxes(uses, place.uses, (list) => {
      voice.setPlace(place.section, { uses: list });
      changed();
      rerender();
    }), null, hint(t, 'help.place.use', { label: t('places.uses'), choices: choiceTopics('help.place.use', uses) })));
}

function placesPanel(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  const list = voice.places(model);
  const max = catalog.sheet.maxPlaces;
  const ask = h('div', { class: 'notice-host' });
  const panel = fold(t('places.title', { n: list.length }), list.length === 0 || ctx.ui.open_place,
    h('p', { class: 'help', text: t('places.help') }),
    h('div', { class: 'cards' }, list.map((place, index) => placeCard(ctx, place, index))),
    ask,
    button('add', { disabled: max && list.length >= max, onClick: async () => {
      // The name first: the place's id is made from it once, and never changes afterwards (missions refer to it).
      const label = await askBar(ask, t, { message: t('places.ask'), label: t('places.label'), ok: t('places.add_ok'),
        check: (v) => (v ? null : t('places.ask')) });
      if (label === null) return;
      voice.addPlace(model, { label, at: { x: '', y: '', z: '0' }, uses: [] });
      ctx.ui.open_place = true;
      changed();
      rerender();
    } }, t('places.add')),
    surveysBlock(ctx));
  panel.addEventListener('toggle', () => { ctx.ui.open_place = panel.open; });
  return panel;
}

function paramRows(ctx, mission, type, opts) {
  return Object.entries(type.params).map(([key, kind]) => row(paramLabel(ctx.t, key),
    (id) => field(kind, { t: ctx.t, id, value: sheet.value(mission, key) ?? '', rerender: ctx.rerender,
      onChange: (v) => { sheet.setValue(mission, key, v); ctx.changed(); }, ...opts }),
    ctx.t(`param.${key}.help`, {}, ctx.t(`kind.${kind}.help`, {}, '')),
    hint(ctx.t, paramTopics(type, key, kind), { label: paramLabel(ctx.t, key) })));
}

// What the AI reads of the voice to suggest a story: its name, short description and the start of its personality.
const CONTEXT_CHARS = 1500;
function voiceContext(model) {
  return [sheet.value(model.head, 'name'), sheet.description(model), sheet.promptText(model)]
    .filter(Boolean).join('\n').slice(0, CONTEXT_CHARS);
}

// story= of the mission, with the AI's "Suggest" (E22-T06).
function storyField(ctx, mission, type, id) {
  const { t, changed, model } = ctx;
  const input = textInput(id, sheet.value(mission, 'story'), (v) => {
    sheet.setValue(mission, 'story', v);
    changed();
  }, { maxlength: 200, lang: 'en', placeholder: t('mission.story_placeholder') });
  const suggest = suggestButton({ ai: ctx.ai, t, voiceId: ctx.voiceId, missionType: sheet.value(mission, 'type') ?? '',
    voiceText: type?.voiceText ?? '', context: voiceContext(model),
    setStory: (text) => { input.value = text; sheet.setValue(mission, 'story', text); changed(); } });
  return h('div', { class: 'inline grow' }, input, suggest);
}

function missionCard(ctx, mission, index, opts) {
  const { model, catalog, t, changed, rerender } = ctx;
  const type = catalog.missionType(sheet.value(mission, 'type'));
  const others = voice.missions(model).filter((m) => m !== mission)
    .map((m) => ({ value: m.id, label: `${m.id} (${t(`mission.${sheet.value(m, 'type')}`, {}, sheet.value(m, 'type') ?? '?')})` }));
  const missionGrammar = catalog.section('mission');
  const scopes = (missionGrammar?.choices.scope ?? []).map((v) => choice(t, 'choice.scope', v));
  const typeChoices = catalog.missionTypes().map((m) => ({ label: typeTitle(t, m), topic: `help.mission_type.${m.name}` }));
  const changeType = (name) => {
    const next = catalog.missionType(name);
    for (const key of Object.keys(type?.params ?? {})) if (!(next && key in next.params)) sheet.setValue(mission, key, null);
    sheet.setValue(mission, 'type', name);
    changed();
    rerender();
  };
  const typeOptions = catalog.missionTypes().map((m) => ({ value: m.name, label: typeTitle(t, m) }));
  return h('article', { class: 'card mission' },
    h('header', { class: 'card-head' },
      h('span', { class: 'num-badge', text: String(index + 1) }),
      h('b', { text: type ? typeTitle(t, type) : (sheet.value(mission, 'type') ?? '?') }),
      type && typeHint(t, type),
      h('code', { text: mission.id }),
      removeButton(t, () => { sheet.removeSection(model, mission); changed(); rerender(); }, t('missions.remove'))),
    type && h('p', { class: 'help', text: typeHelp(t, type) }),
    row(t('missions.type'), (id) => select(typeOptions, sheet.value(mission, 'type') ?? '', changeType, { id }), null,
      hint(t, 'help.mission.type', { label: t('missions.type'), choices: typeChoices })),
    row(t('mission.story'), (id) => storyField(ctx, mission, type, id), t('mission.story_help'),
      hint(t, 'help.mission.story', { label: t('mission.story') })),
    type && type.setups.map((setup) => SETUP_FIELDS[setup]?.(ctx, mission, opts)),
    type && paramRows(ctx, mission, type, opts),
    row(t('mission.after'), (id) => select([{ value: '', label: t('mission.after_none') }, ...others],
      sheet.value(mission, 'after') ?? '', (v) => { sheet.setValue(mission, 'after', v); changed(); }, { id }),
    t('mission.after_help'), hint(t, 'help.mission.after', { label: t('mission.after') })),
    fold(t('mission.more'), false,
      !type?.setups.includes('aimAt') && row(t('mission.target'), (id) => select(
        [{ value: '', label: t('mission.target_any') }, ...opts.places], sheet.value(mission, 'target') ?? '',
        (v) => { sheet.setValue(mission, 'target', v); changed(); }, { id }), t('mission.target_optional'),
      hint(t, 'help.mission.target', { label: t('mission.target') })),
      row(t('mission.weight'), (id) => chanceChoice(t, voice.missionWeight(model, mission),
        (v) => { voice.setMissionWeight(model, mission, v); changed(); }, { id }), t('mission.weight_help'),
      hint(t, 'help.mission.weight', { label: t('mission.weight') })),
      row(t('mission.scope'), (id) => {
        const scope = select(scopes, sheet.value(mission, 'scope') ?? 'character',
          (v) => { sheet.setValue(mission, 'scope', v === 'character' ? null : v); changed(); }, { id });
        return h('div', { class: 'stack' }, scope, selectHelp(t, 'help.mission.scope', scope));
      }, t('mission.scope_help'),
      hint(t, 'help.mission.scope', { label: t('mission.scope'), choices: choiceTopics('help.mission.scope', scopes) })),
      row(t('mission.sets_state'), (id) => textInput(id, sheet.value(mission, 'sets_state'), (v) => {
        sheet.setValue(mission, 'sets_state', v);
        changed();
      }, { spellcheck: 'false' }), t('mission.sets_state_help'),
      hint(t, 'help.mission.sets_state', { label: t('mission.sets_state') }))));
}

function addMissionPanel(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  return h('div', { class: 'stack' },
    h('h3', { text: t('missions.add') }),
    h('div', { class: 'type-cards' }, catalog.missionTypes().map((type) => h('div', { class: 'type-card-wrap' },
      button('neutral', { class: 'type-card', onClick: () => {
        const created = voice.addMission(model, type.name);
        if (type.setups.includes('aimAt') && voice.places(model).some((p) => p.uses.includes('target'))) {
          sheet.setValue(created, 'target', voice.places(model).find((p) => p.uses.includes('target')).id);
        }
        changed();
        rerender();
      } }, h('b', { text: typeTitle(t, type) }), h('small', { text: typeHelp(t, type) })),
      typeHint(t, type)))));
}

export default {
  id: 'missions',
  fields: [],
  blocks: ['place', 'mission'],
  render(ctx) {
    const { model, t } = ctx;
    const opts = fieldOptions(model, ctx.catalog, t);
    const missions = voice.missions(model);
    return h('div', { class: 'form' },
      h('p', { class: 'q', text: t('missions.question') }),
      placesPanel(ctx),
      missions.length === 0 && h('p', { class: 'muted', text: t('missions.none') }),
      h('div', { class: 'cards' }, missions.map((m, i) => missionCard(ctx, m, i, opts))),
      addMissionPanel(ctx));
  },
};
