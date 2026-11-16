// Step 4, places and missions: the places of the voice ([place]: name, square, uses) and her missions ([mission]). Every
// mission form is generated from the catalogue: its type's parameters (field by kind, or named steps when scales.js has
// a scale "mission.<key>"), its voice set-ups (target place, dead drops) and the [mission] keys. A mission type added to
// the mod shows up here without any change. Ids of places and missions are made by the page and never shown (E24-T02).

import { suggestButton } from '../ai.js';
import { askBar } from '../dialogs.js';
import { h, select } from '../dom.js';
import { field, fieldOptions } from '../fields.js';
import { choiceTopics, hint, selectHelp } from '../help.js';
import { mapLink } from '../maplink.js';
import { scaleOf } from '../scales.js';
import * as sheet from '../sheet.js';
import { stepChoice } from '../stepchoice.js';
import * as story from '../story.js';
import { surveysBlock } from '../surveys.js';
import { formatList, parseList } from '../values.js';
import * as voice from '../voice.js';
import { button, chanceChoice, checkboxes, choice, fold, removeButton, row, textInput } from '../widgets.js';

const STORY_MAX = 200;
const LABEL_MAX = 48;

const typeTitle = (t, type) => t(`mission.${type.name}`, {}, type.name);
const typeIcon = (t, type) => t(`mission.${type.name}.icon`, {}, '');
const typeHelp = (t, type) => t(`mission.${type.name}.help`, {}, type.voiceText);
const paramLabel = (t, key) => t(`param.${key}`, {}, key);
// Help of a parameter: of this type, else of the parameter name, else of its kind (help.js picks the first found).
const paramTopics = (type, key, kind) => [`help.mission_type.${type.name}.${key}`, `help.param.${key}`, `help.param_kind.${kind}`];
// "?" of a mission type: what it is, what the player does, and its own settings.
const typeHint = (t, type) => hint(t, `help.mission_type.${type.name}`, { label: typeTitle(t, type),
  choicesTitle: t('hint.settings'),
  choices: Object.entries(type.params).map(([key, kind]) => ({ label: paramLabel(t, key), topic: paramTopics(type, key, kind) })) });

// A text field with its live count "12 / 48" (charter: limits said, never in bytes).
function countedInput(id, value, max, onInput, attrs = {}) {
  const counter = h('small', { class: 'counter', 'aria-live': 'polite' });
  const show = (text) => { counter.textContent = `${[...String(text ?? '')].length} / ${max}`; };
  const input = textInput(id, value, (v) => { show(v); onInput(v); }, { maxlength: max, ...attrs });
  show(value);
  return { input, counter };
}

// Where the mission happens (target=): one label for every type, a red "needed" pill when the type needs a place.
function targetRow(ctx, mission, opts, needed) {
  const { t, changed } = ctx;
  const label = h('span', {}, t('mission.target'), needed && h('span', { class: 'pill-needed', text: t('field.needed') }));
  return row(label, (id) => select([{ value: '', label: needed ? t('field.choose') : t('mission.target_any') }, ...opts.places],
    sheet.value(mission, 'target') ?? '', (v) => { sheet.setValue(mission, 'target', v || null); changed(); }, { id }),
  needed ? t('mission.target_help') : t('mission.target_optional'),
  hint(t, 'help.mission.target', { label: t('mission.target') }));
}

// Set-up of a mission type -> the [mission] key it reads (shown only for the types that declare it).
const SETUP_FIELDS = {
  aimAt: (ctx, mission, opts) => targetRow(ctx, mission, opts, true),
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
  const uses = catalog.placeUses().map((u) => ({ ...choice(t, 'use', u), label: `${t(`use.${u}.icon`, {}, '')} ${t(`use.${u}`)}`.trim() }));
  const map = mapLink(t, () => at);
  const coord = (key, label) => h('input', { type: 'number', step: 1, class: 'num', value: at[key], 'aria-label': label,
    onInput: (e) => { at[key] = e.target.value; voice.setPlace(place.section, { at }); changed(); map.refresh(); } });
  const name = countedInput(null, place.label, LABEL_MAX, (v) => { voice.setPlace(place.section, { label: v }); changed(); });
  return h('article', { class: `card place${ctx.ui.new_place === place.id ? ' fresh' : ''}`, title: place.id },
    h('header', { class: 'card-head' },
      h('b', { text: place.label || t('places.unnamed', { n: index + 1 }) }),
      removeButton(t, () => { sheet.removeSection(model, place.section); changed(); rerender(); }, t('places.remove'))),
    row(t('places.label'), (id) => h('div', { class: 'inline grow' }, Object.assign(name.input, { id }), name.counter),
      t('places.label_help'), hint(t, 'help.place.label', { label: t('places.label') })),
    row(t('places.at'), (id) => h('div', { class: 'inline', id }, 'x', coord('x', 'x'), 'y', coord('y', 'y'),
      t('places.floor'), coord('z', t('places.floor')), map.el),
    t('places.at_help'), hint(t, 'help.place.at', { label: t('places.at') })),
    row(t('places.uses'), () => checkboxes(uses, place.uses, (list) => {
      voice.setPlace(place.section, { uses: list });
      changed();
      rerender();
    }, { class: 'checks chips' }), null, hint(t, 'help.place.use', { label: t('places.uses'), choices: choiceTopics('help.place.use', uses) })));
}

// A new place: its name asked, its square typed in its card (user decision 2026-11-16) or taken from the places
// recorded in game (surveys.js). `uses` are ticked from the start (a trade meeting point made from the trade panel).
async function newPlace(ctx, host, uses = []) {
  const { model, t } = ctx;
  const label = await askBar(host, t, { message: t('places.ask'), label: t('places.label'), ok: t('places.add_ok'),
    value: uses.length ? t(`use.${uses[0]}`) : '', check: (v) => (v ? null : t('places.ask')) });
  if (label === null) return null;
  const created = voice.addPlace(model, { label, at: { x: '', y: '', z: '0' }, uses });
  Object.assign(ctx.ui, { open_place: true, new_place: created.id });
  ctx.changed();
  ctx.rerender();
  return created;
}

function placesPanel(ctx) {
  const { model, catalog, t } = ctx;
  const list = voice.places(model);
  const max = catalog.sheet.maxPlaces;
  const ask = h('div', { class: 'notice-host' });
  const panel = fold(t('places.title', { n: list.length }), list.length === 0 || ctx.ui.open_place,
    list.length === 0 && h('p', { class: 'empty', text: t('places.empty') }),
    h('div', { class: 'cards' }, list.map((place, index) => placeCard(ctx, place, index))),
    ask,
    button('add', { id: 'place-new', disabled: max && list.length >= max, onClick: () => newPlace(ctx, ask) }, t('places.add')),
    surveysBlock(ctx));
  panel.addEventListener('toggle', () => { ctx.ui.open_place = panel.open; });
  return panel;
}

// Settings of a mission type, in one box: named steps when the parameter has a scale, else the field of its kind.
function paramRows(ctx, mission, type, opts) {
  const { t } = ctx;
  return Object.entries(type.params).map(([key, kind]) => row(paramLabel(t, key), (id) => (scaleOf('mission', key)
    ? stepChoice(t, 'mission', key, sheet.value(mission, key), (v) => { sheet.setValue(mission, key, v); ctx.changed(); }, { id })
    : field(kind, { t, id, value: sheet.value(mission, key) ?? '', rerender: ctx.rerender, label: paramLabel(t, key),
      onChange: (v) => { sheet.setValue(mission, key, v === '' ? null : v); ctx.changed(); }, ...opts })),
  t(`param.${key}.help`, {}, t(`kind.${kind}.help`, {}, '')),
  hint(t, paramTopics(type, key, kind), { label: paramLabel(t, key) })));
}

// What the AI reads of the voice to suggest a story: its name, short description and the start of its personality.
const CONTEXT_CHARS = 1500;
function voiceContext(model) {
  return [sheet.value(model.head, 'name'), sheet.description(model), sheet.promptText(model)]
    .filter(Boolean).join('\n').slice(0, CONTEXT_CHARS);
}

// story= of the mission: the AI's "Suggest" first, then the text and its count (E22-T06).
function storyField(ctx, mission, type, id) {
  const { t, changed, model } = ctx;
  const text = countedInput(id, sheet.value(mission, 'story'), STORY_MAX, (v) => {
    sheet.setValue(mission, 'story', v);
    changed();
  }, { placeholder: t('mission.story_placeholder') });
  const suggest = suggestButton({ ai: ctx.ai, t, voiceId: ctx.voiceId, missionType: sheet.value(mission, 'type') ?? '',
    voiceText: type?.voiceText ?? '', context: voiceContext(model),
    setStory: (said) => { text.input.value = said; text.input.dispatchEvent(new Event('input')); } });
  return h('div', { class: 'inline grow' }, suggest, text.input, text.counter);
}

// The mission's story state as a sentence; its name is made by story.js and never shown.
function storyStateRow(ctx, mission) {
  const { t, model, changed } = ctx;
  return row(t('mission.sets_state'), (id) => textInput(id, story.sentence(model, mission), (v) => {
    story.setStory(model, mission, v);
    changed();
  }, { placeholder: t('mission.sets_state_placeholder'), maxlength: 120 }), t('mission.sets_state_help'),
  hint(t, 'help.mission.sets_state', { label: t('mission.sets_state') }));
}

function missionCard(ctx, mission, index, opts) {
  const { model, catalog, t, changed, rerender } = ctx;
  const type = catalog.missionType(sheet.value(mission, 'type'));
  const all = voice.missions(model);
  const others = all.filter((m) => m !== mission).map((m) => ({ value: m.id,
    label: `${all.indexOf(m) + 1} · ${t(`mission.${sheet.value(m, 'type')}`, {}, sheet.value(m, 'type') ?? '?')}` }));
  const scopes = (catalog.section('mission')?.choices.scope ?? []).map((v) => choice(t, 'choice.scope', v));
  const typeChoices = catalog.missionTypes().map((m) => ({ label: typeTitle(t, m), topic: `help.mission_type.${m.name}` }));
  const changeType = (name) => {
    const next = catalog.missionType(name);
    for (const key of Object.keys(type?.params ?? {})) if (!(next && key in next.params)) sheet.setValue(mission, key, null);
    sheet.setValue(mission, 'type', name);
    changed();
    rerender();
  };
  const typeOptions = catalog.missionTypes().map((m) => ({ value: m.name, label: `${typeIcon(t, m)} ${typeTitle(t, m)}`.trim() }));
  return h('article', { class: 'card mission', title: mission.id },
    h('header', { class: 'card-head' },
      h('span', { class: 'num-badge', text: String(index + 1) }),
      h('b', { text: type ? `${typeIcon(t, type)} ${typeTitle(t, type)}`.trim() : (sheet.value(mission, 'type') ?? '?') }),
      type && typeHint(t, type),
      removeButton(t, () => { sheet.removeSection(model, mission); changed(); rerender(); }, t('missions.remove'))),
    type && h('p', { class: 'help', text: typeHelp(t, type) }),
    row(t('mission.story'), (id) => storyField(ctx, mission, type, id), t('mission.story_help'),
      hint(t, 'help.mission.story', { label: t('mission.story') })),
    type && type.setups.map((setup) => SETUP_FIELDS[setup]?.(ctx, mission, opts)),
    type && Object.keys(type.params).length > 0 && h('div', { class: 'settings' }, paramRows(ctx, mission, type, opts)),
    row(t('mission.after'), (id) => select([{ value: '', label: t('mission.after_none') }, ...others],
      sheet.value(mission, 'after') ?? '', (v) => { sheet.setValue(mission, 'after', v || null); changed(); }, { id }),
    t('mission.after_help'), hint(t, 'help.mission.after', { label: t('mission.after') })),
    storyStateRow(ctx, mission),
    fold(t('mission.more'), false,
      row(t('missions.type'), (id) => select(typeOptions, sheet.value(mission, 'type') ?? '', changeType, { id }), null,
        hint(t, 'help.mission.type', { label: t('missions.type'), choices: typeChoices })),
      !type?.setups.includes('aimAt') && targetRow(ctx, mission, opts, false),
      row(t('mission.weight'), (id) => chanceChoice(t, voice.missionWeight(model, mission),
        (v) => { voice.setMissionWeight(model, mission, v); changed(); }, { id }), t('mission.weight_help'),
      hint(t, 'help.mission.weight', { label: t('mission.weight') })),
      row(t('mission.scope'), (id) => {
        const scope = select(scopes, sheet.value(mission, 'scope') ?? 'character',
          (v) => { sheet.setValue(mission, 'scope', v === 'character' ? null : v); changed(); }, { id });
        return h('div', { class: 'stack' }, scope, selectHelp(t, 'help.mission.scope', scope));
      }, t('mission.scope_help'),
      hint(t, 'help.mission.scope', { label: t('mission.scope'), choices: choiceTopics('help.mission.scope', scopes) }))));
}

function addMissionPanel(ctx) {
  const { model, catalog, t, changed, rerender } = ctx;
  return h('div', { class: 'stack' },
    h('h3', { text: t('missions.add') }),
    h('div', { class: 'type-cards' }, catalog.missionTypes().map((type) => h('div', { class: 'type-card-wrap' },
      button('neutral', { class: 'type-card', 'data-type': type.name, onClick: () => {
        const created = voice.addMission(model, type.name);
        if (type.setups.includes('aimAt') && voice.places(model).some((p) => p.uses.includes('target'))) {
          sheet.setValue(created, 'target', voice.places(model).find((p) => p.uses.includes('target')).id);
        }
        changed();
        rerender();
      } }, h('span', { class: 'card-icon', 'aria-hidden': 'true', text: typeIcon(t, type) }),
      h('b', { text: typeTitle(t, type) }), h('small', { text: typeHelp(t, type) })),
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
    const adding = addMissionPanel(ctx);
    return h('div', { class: 'form' },
      placesPanel(ctx),
      h('h3', { class: 'step-sub', text: t('missions.question') }),
      missions.length === 0 && h('p', { class: 'empty', text: t('missions.none') }),
      missions.length === 0 && adding,
      h('div', { class: 'cards' }, missions.map((m, i) => missionCard(ctx, m, i, opts))),
      missions.length > 0 && adding);
  },
};
