// Step 4, map marks and missions: the shared places the voice may give on the map (marks=, E25-T03) and her missions
// ([mission]). Every mission form is generated from the catalogue: its type's parameters (field by kind, or named steps
// when scales.js has a scale "mission.<key>"), its voice set-ups (dead drops) and the [mission] keys. Where a mission
// happens is a shared place, or a building drawn near, further or far from the player (E25-T01), of a kind in plain
// words. A mission type added to the mod shows up here without any change. Ids of missions are made by the page and
// never shown (E24-T02); places are picked in lists of the shared places (placeform.js), with "New place…".

import { inputPropose } from '../ai.js';
import { h, select } from '../dom.js';
import { field, fieldOptions } from '../fields.js';
import { choiceTopics, hint, selectHelp } from '../help.js';
import { placeChecks, placeSelect } from '../placeform.js';
import { ZONE } from '../places.js';
import { scaleOf } from '../scales.js';
import * as sheet from '../sheet.js';
import { stepChoice } from '../stepchoice.js';
import * as story from '../story.js';
import { formatList, parseList } from '../values.js';
import * as voice from '../voice.js';
import { button, chanceChoice, choice, countedInput, fold, removeButton, row, textInput } from '../widgets.js';

const STORY_MAX = 200;
// Set-ups that give a mission type places of its own (dead drops to deliver to, route points): no objective then.
const OWN_PLACES_SETUPS = ['askFor', 'alongPoints'];

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

// Where the mission happens (target=, E25-T01): near the player when nothing is written (the game's default), further,
// far, or a shared place; a building kind ("Any" or one of CA_Sites.KINDS in words) for an area or a distance.
function objectiveRows(ctx, mission) {
  const { t, catalog, changed, rerender } = ctx;
  const distances = catalog.distances();
  const target = sheet.value(mission, 'target') ?? distances[0];
  const drawn = distances.includes(target) || ctx.places.find(target)?.kind === ZONE;
  const extra = distances.map((d) => ({ value: d, label: `${t(`objective.${d}.icon`)} ${t(`objective.${d}`)}` }));
  const kinds = [{ value: '', label: t('building.any') }, ...catalog.buildings().map((k) => ({ value: k, label: t(`building.${k}`) }))];
  return [
    row(t('mission.target'), (id) => placeSelect(ctx, target, (v) => {
      sheet.setValue(mission, 'target', v === distances[0] ? null : v);
      if (!(distances.includes(v) || ctx.places.find(v)?.kind === ZONE)) sheet.setValue(mission, 'building', null);
      changed();
      rerender();
    }, { extra, id }), t('mission.target_help'), hint(t, 'help.mission.target', { label: t('mission.target') })),
    drawn && row(t('mission.building'), (id) => select(kinds, sheet.value(mission, 'building') ?? '', (v) => {
      sheet.setValue(mission, 'building', v || null);
      changed();
    }, { id, class: 'building-select' }), t('mission.building_help'),
    hint(t, 'help.mission.building', { label: t('mission.building') })),
  ];
}

// Set-up of a mission type -> the [mission] key it reads (shown only for the types that declare it).
const SETUP_FIELDS = {
  dropAccepts: (ctx, mission) => row(h('span', {}, ctx.t('mission.drops'),
    h('span', { class: 'pill-needed', text: ctx.t('field.needed') })), (id) => placeChecks(ctx,
    parseList(sheet.value(mission, 'drops')), (list) => {
      sheet.setValue(mission, 'drops', formatList(list));
      ctx.changed();
      ctx.rerender();
    }, { points: true, id }), ctx.t('mission.drops_help'),
  hint(ctx.t, 'help.mission.drops', { label: ctx.t('mission.drops') })),
};

// The map marks the voice may give (marks=, E25-T01): shared places, spots or areas, ticked in a list.
function marksQuestion(ctx) {
  const { t, model, changed, rerender } = ctx;
  return h('section', { class: 'question marks' },
    h('h3', {}, t('marks.question'), ' ', hint(t, 'help.head.marks', { label: t('marks.question') })),
    h('p', { class: 'help', text: t('marks.help') }),
    placeChecks(ctx, voice.marks(model), (list) => { voice.setMarks(model, list); changed(); rerender(); },
      { id: 'marks' }));
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

// What the AI is told of a mission when it proposes its story or its story state: which mission, its type and what the
// player does, its place and its settings in words.
function missionDetails(ctx, mission, type, index) {
  const { t } = ctx;
  const aim = sheet.value(mission, 'target') ?? ctx.catalog.distances()[0];
  const target = ctx.places.find(aim);
  const settings = Object.keys(type?.params ?? {}).map((key) => [paramLabel(t, key), sheet.value(mission, key)])
    .filter(([, value]) => value).map(([label, value]) => `${label}: ${value}`).join('; ');
  return { mission_id: mission.id, mission_number: String(index + 1),
    mission_type: type ? typeTitle(t, type) : sheet.value(mission, 'type'),
    what_the_player_does: type ? [type.voiceText, typeHelp(t, type)].filter(Boolean).join(' / ') : null,
    target_place: target?.label || t(`objective.${aim}`, {}, aim ?? '') || null, settings };
}

// story= of the mission: the text, its count and the AI's "Suggest" (E22-T06, E24-T04).
function storyField(ctx, mission, type, index, id) {
  const { t, changed } = ctx;
  const text = countedInput(id, sheet.value(mission, 'story'), STORY_MAX, (v) => {
    sheet.setValue(mission, 'story', v);
    changed();
  }, { placeholder: t('mission.story_placeholder') });
  const propose = inputPropose(ctx, 'mission_story', text.input, { details: () => missionDetails(ctx, mission, type, index) });
  return h('div', { class: 'inline grow' }, text.input, text.counter, propose);
}

// The mission's story state as a sentence; its name is made by story.js and never shown.
function storyStateRow(ctx, mission, type, index) {
  const { t, model, changed } = ctx;
  return row(t('mission.sets_state'), (id) => {
    const input = textInput(id, story.sentence(model, mission), (v) => {
      story.setStory(model, mission, v);
      changed();
    }, { placeholder: t('mission.sets_state_placeholder'), maxlength: 120 });
    return h('div', { class: 'inline grow' }, input, inputPropose(ctx, 'mission_state', input, {
      details: () => ({ ...missionDetails(ctx, mission, type, index), mission_story: sheet.value(mission, 'story') }) }));
  }, t('mission.sets_state_help'),
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
    row(t('mission.story'), (id) => storyField(ctx, mission, type, index, id), t('mission.story_help'),
      hint(t, 'help.mission.story', { label: t('mission.story') })),
    type && !type.setups.some((setup) => OWN_PLACES_SETUPS.includes(setup)) && objectiveRows(ctx, mission),
    type && type.setups.map((setup) => SETUP_FIELDS[setup]?.(ctx, mission, opts)),
    type && Object.keys(type.params).length > 0 && h('div', { class: 'settings' }, paramRows(ctx, mission, type, opts)),
    row(t('mission.after'), (id) => select([{ value: '', label: t('mission.after_none') }, ...others],
      sheet.value(mission, 'after') ?? '', (v) => { sheet.setValue(mission, 'after', v || null); changed(); }, { id }),
    t('mission.after_help'), hint(t, 'help.mission.after', { label: t('mission.after') })),
    storyStateRow(ctx, mission, type, index),
    fold(t('mission.more'), false,
      row(t('missions.type'), (id) => select(typeOptions, sheet.value(mission, 'type') ?? '', changeType, { id }), null,
        hint(t, 'help.mission.type', { label: t('missions.type'), choices: typeChoices })),
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
        voice.addMission(model, type.name);
        changed();
        rerender();
      } }, h('span', { class: 'card-icon', 'aria-hidden': 'true', text: typeIcon(t, type) }),
      h('b', { text: typeTitle(t, type) }), h('small', { text: typeHelp(t, type) })),
      typeHint(t, type)))));
}

export default {
  id: 'missions',
  fields: ['marks'],
  blocks: ['mission'],
  render(ctx) {
    const { model, t } = ctx;
    const opts = fieldOptions(ctx, t);
    const missions = voice.missions(model);
    const adding = addMissionPanel(ctx);
    return h('div', { class: 'form' },
      marksQuestion(ctx),
      h('h3', { class: 'step-sub', text: t('missions.question') }),
      missions.length === 0 && h('p', { class: 'empty', text: t('missions.none') }),
      missions.length === 0 && adding,
      h('div', { class: 'cards' }, missions.map((m, i) => missionCard(ctx, m, i, opts))),
      missions.length > 0 && adding);
  },
};
