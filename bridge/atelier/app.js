// Voice workshop page (E22-T03, E22-T05, E22-T04, E22-T10; ADR atelier-voix): composition root. Loads the strings
// and the catalogue, lists the voices, runs the five-step assistant over a sheet model, saves, exports, imports,
// deletes, removes and restores through the server API. Every choice comes from the catalogue; the game stays the only
// judge (D03): its verdict is polled and shown on the voice and the step of the refused line. The "Dashboard" tab, shown
// first, sums up every voice (E24-T05); the "Places" tab edits the places every voice shares (E25-T03, placestab.js,
// one place store for the tab and the place lists of the editor); the "Journal" tab shows the live lines of the bridge and the game (D09). The bridge's AI helps to write and lets the voice be tried (D04,
// ai.js).

import { fillField, proposeButton, tryDrawer } from './ai.js';
import { LOGIN_PAGE, createApi } from './api.js';
import { loadCatalog } from './catalog.js';
import { check } from './checks.js';
import { createDashboard } from './dashboard.js';
import { confirmBar } from './dialogs.js';
import { clear, h, select } from './dom.js';
import { loadI18n } from './i18n.js';
import { masterDetail } from './masterdetail.js';
import { createJournal } from './journal.js';
import { createPlaceStore } from './placestore.js';
import { createPlacesView } from './placestab.js';
import * as sheet from './sheet.js';
import * as voice from './voice.js';
import { renderVerdict } from './verdict.js';
import { STEP_WANTS, VOICE_TYPES, applyVoiceType, stepWanted } from './presets.js';
import { renderVoiceList, voiceStatus } from './voicelist.js';
import { button, cards } from './widgets.js';
import who from './steps/who.js';
import where from './steps/where.js';
import personality from './steps/personality.js';
import missions from './steps/missions.js';
import rewards from './steps/rewards.js';

const STEPS = [who, where, personality, missions, rewards];
const VERDICT_POLL_MS = 4000;

// What can be done to a voice in each state (server routes of bridge/atelier_server.py).
const ACTIONS = {
  delete: { label: 'action_delete', ask: 'confirm.delete', danger: true, run: (api, id) => api.remove(id) },
  remove: { label: 'action_remove', ask: 'confirm.remove', danger: true, run: (api, id) => api.silence(id) },
  restore: { label: 'action_restore', ask: 'confirm.restore', danger: false, run: (api, id) => api.restore(id) },
};
const ACTIONS_BY_STATUS = {
  custom: ['delete'], delivered: ['remove'], outdated: ['restore', 'remove'], modified: ['restore', 'remove'], removed: ['restore'],
};

const app = {
  t: null, catalog: null, api: createApi(), voices: [], current: null, step: 0, preview: false, ui: {},
  places: null,                                     // E25-T03: the shared places (placestore.js)
  verdicts: {}, views: {}, el: {}, login: false, // login: network mode (E22-T15), the header offers to log out
  ai: { available: false, api: null, toast: null }, // E22-T06: the bridge's AI (greyed when not configured)
  chat: { open: false, messages: [] },              // test conversation of the voice being edited
};

// Whether the bridge has an AI configured (set just after the page opens: asked again for each voice opened).
async function refreshAi() {
  const result = await app.api.status();
  app.ai.available = Boolean(result.ok && result.ai);
  app.login = Boolean(result.ok && result.login);
  return result;
}

async function logout() {
  await app.api.logout();
  window.location.assign(LOGIN_PAGE);
}

// --- messages -------------------------------------------------------------------------------------------------------
function codeText(result) {
  return app.t(`code.${result.code}`, { id: result.id ?? '' }, result.message || result.code);
}

// A message goes away by itself (an error stays longer); a click dismisses it at once.
const TOAST_MS = 3000;
const TOAST_BAD_MS = 7000;
let toastTimer = null;
function toast(text, bad = false) {
  const el = app.el.toast;
  el.textContent = text;
  el.className = bad ? 'toast bad show' : 'toast show';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.className = 'toast'; }, bad ? TOAST_BAD_MS : TOAST_MS);
}

// --- voices ---------------------------------------------------------------------------------------------------------
async function refreshVoices() {
  const result = await app.api.voices();
  if (!result.ok) { toast(codeText(result), true); return; }
  app.voices = result.voices;
  renderVoiceList(app.el.side, { t: app.t, voices: app.voices, currentId: app.current?.id, onOpen: openVoice, onNew: showNewVoice,
    verdicts: app.verdicts });
}

// --- the game's verdict (E22-T04) -----------------------------------------------------------------------------------
async function refreshVerdicts() {
  const result = await app.api.verdicts();
  if (!result.ok) return;
  if (JSON.stringify(result.verdicts) === JSON.stringify(app.verdicts)) return;
  app.verdicts = result.verdicts ?? {};
  renderVoiceList(app.el.side, { t: app.t, voices: app.voices, currentId: app.current?.id, onOpen: openVoice, onNew: showNewVoice,
    verdicts: app.verdicts });
  renderVerdictBanner();
  app.views?.dashboard?.redraw?.();
}

function pollVerdicts() {
  const again = () => setTimeout(pollVerdicts, VERDICT_POLL_MS);
  if (document.hidden) { again(); return; }
  refreshVerdicts().finally(again);
}

// Step owning line `line` of the sheet as the game read it (the text last loaded or saved).
function verdictTarget(line) {
  if (!line || app.current.saved === undefined) return null;
  const index = stepOf({ where: sheet.locate(app.current.saved, line) });
  return { step: app.t(`step.${STEPS[index].id}`), go: () => { app.ui.all_steps = true; goStep(index); } };
}

function renderVerdictBanner() {
  const host = app.el.verdict;
  if (!host || !app.current || app.current.isNew) return;
  const verdict = app.verdicts[app.current.id];
  const banner = renderVerdict(verdict, { t: app.t, target: verdict?.state === 'refused' ? verdictTarget(verdict.line) : null });
  host.replaceChildren(...(banner ? [banner] : []));
}

const entryOf = (id) => app.voices.find((v) => v.id === id) ?? null;

async function leaveCurrent() {
  if (!app.current?.dirty) return true;
  return confirmBar(app.el.notice, app.t, { message: app.t('confirm.leave'), yes: app.t('confirm.leave_yes'), danger: true });
}

async function openVoice(id) {
  if (!(await leaveCurrent())) return;
  const result = await app.api.read(id);
  if (!result.ok) { toast(codeText(result), true); return; }
  app.current = { id, model: sheet.parse(result.text ?? ''), isNew: false, dirty: false, empty: !(result.text ?? '').trim(),
    saved: result.text ?? '' };
  app.step = 0;
  app.ui = {};
  app.chat.messages = [];
  showView('voices');
  await Promise.all([refreshVoices(), refreshAi()]);
  renderEditor();
}

// --- new voice ------------------------------------------------------------------------------------------------------
// E24-T02: the name, then how to start (from scratch with a voice type, or from a copy of a voice). The voice's id is
// made from its first name and never shown (voice.voiceId).
const START_FROM = ['empty', 'copy'];
const takenIds = () => app.voices.map((v) => v.id);

async function showNewVoice() {
  if (!(await leaveCurrent())) return;
  showView('voices');
  app.current = null;
  await refreshVoices();
  const t = app.t;
  const state = { name: '', from: 'empty', type: VOICE_TYPES[0].id, source: '' };
  const error = h('p', { class: 'warnline', 'aria-live': 'polite' });
  const body = h('div', { class: 'stack' });
  const sources = app.voices.filter((v) => !v.removed).map((v) => ({ value: v.id, label: v.name || v.id }));
  // What the AI knows when it proposes a name: the voice type card picked, or the voice copied (no sheet yet).
  const voiceType = () => {
    if (state.from === 'copy') {
      const source = sources.find((v) => v.value === state.source);
      return source ? `copy of ${source.label}` : null;
    }
    return `${t(`newtype.${state.type}`)}: ${t(`newtype.${state.type}.help`)}`;
  };
  const nameInput = h('input', { type: 'text', id: 'new-name', autocomplete: 'off',
    placeholder: t('who.name_placeholder'), onInput: (e) => { state.name = e.target.value; },
    onKeydown: (e) => { if (e.key === 'Enter') create(); } });
  const proposeName = proposeButton({ ai: app.ai, t, field: 'name', voiceId: null, sheetText: () => '',
    current: () => nameInput.value, details: () => ({ voice_type: voiceType() }),
    apply: (text) => fillField(nameInput, text) });
  const create = async () => {
    if (!state.name.trim()) { error.textContent = t('new.need_name'); app.el.main.querySelector('#new-name').focus(); return; }
    const id = voice.voiceId(state.name, takenIds());
    if (state.from === 'copy') {
      if (!state.source) { error.textContent = t('new.need_source'); return; }
      const result = await app.api.duplicate(state.source, id);
      if (!result.ok) { error.textContent = codeText(result); return; }
      toast(codeText(result));
      await openVoice(id);
      return;
    }
    const model = voice.newVoice({ id, name: state.name.trim(), radio: app.catalog.radioLevels()[0]?.id,
      format: app.catalog.sheet.format });
    applyVoiceType(model, state.type);
    app.current = { id, model, isNew: true, dirty: true, empty: false };
    app.step = 0;
    app.ui = {};
    app.chat.messages = [];
    await refreshAi();
    renderEditor();
  };
  const draw = () => {
    const starts = START_FROM.map((v) => ({ value: v, label: t(`new.from.${v}`), help: t(`new.from.${v}.help`),
      icon: t(`new.from.${v}.icon`) }));
    const types = VOICE_TYPES.map((v) => ({ value: v.id, label: t(`newtype.${v.id}`), help: t(`newtype.${v.id}.help`),
      icon: t(`newtype.${v.id}.icon`) }));
    body.replaceChildren(
      cards('new-from', starts, state.from, (v) => { state.from = v; draw(); }, { 'aria-label': t('new.start_from') }),
      state.from === 'empty'
        ? h('div', { class: 'stack' }, h('h3', { text: t('new.type') }),
          cards('new-type', types, state.type, (v) => { state.type = v; }, { id: 'new-type', 'aria-label': t('new.type') }),
          h('p', { class: 'help', text: t('new.type_help') }))
        : h('div', { class: 'stack' }, h('label', { for: 'new-source', text: t('new.copy_of') }),
          select([{ value: '', label: t('field.choose') }, ...sources], state.source, (v) => { state.source = v; },
            { id: 'new-source' })));
  };
  draw();
  clear(app.el.main).append(h('article', { class: 'welcome' },
    h('h2', { text: t('new.title') }),
    h('div', { class: 'form' },
      h('div', { class: 'row' }, h('div', { class: 'lab' }, h('label', { for: 'new-name', text: t('who.name') })),
        h('div', { class: 'ctl' }, h('div', { class: 'inline grow' }, nameInput, proposeName))),
      body,
      error,
      h('div', { class: 'btns' }, button('primary', { id: 'new-create', onClick: create }, t('new.create'))))));
  app.el.main.querySelector('#new-name').focus();
}

// --- editor ---------------------------------------------------------------------------------------------------------
function stepOf(item) {
  const { block, field } = item.where;
  const index = block === 'head'
    ? STEPS.findIndex((s) => (s.fields ?? []).includes(field) || (field && field.startsWith('budget.') && (s.fields ?? []).includes('budget')))
    : STEPS.findIndex((s) => (s.blocks ?? []).includes(block));
  return index < 0 ? 0 : index;
}

function currentId() {
  return app.current.isNew ? (sheet.value(app.current.model.head, 'id') ?? '') : app.current.id;
}

// Steps shown in the bar (E24-T02): the ones the voice wants (presets.js STEP_WANTS), the open one, or all of them once
// "All steps" is pressed. Indexes in STEPS.
function shownSteps() {
  return STEPS.map((step, index) => index).filter((index) => app.ui.all_steps || index === app.step
    || stepWanted(STEP_WANTS[STEPS[index].id], app.current.model));
}

// The CURRENT UNSAVED sheet text: what the AI reads to try the voice and to propose a text (E24-T04).
const sheetText = () => sheet.serialize(app.current.model);

function stepContext() {
  return {
    model: app.current.model, catalog: app.catalog, t: app.t, voiceId: currentId(), isNew: app.current.isNew,
    voices: app.voices, ui: app.ui, ai: app.ai, api: app.api, changed, rerender: renderStep, show: showBlock,
    sheetText, toast, places: app.places, voiceName: sheet.value(app.current.model.head, 'name') ?? '',
  };
}

// Checks of the voice being edited, with the shared places it may name.
const checksOf = (model, id) => check(model, app.catalog, id, app.places.list());

// Opens the step that holds a kind of block ('place', 'trade'...) with its panel open (ui.open_<kind>).
function showBlock(kind) {
  app.ui[`open_${kind}`] = true;
  app.ui.all_steps = true;
  goStep(STEPS.findIndex((s) => (s.blocks ?? []).includes(kind)));
}

function changed() {
  app.current.dirty = true;
  refreshStatus();
}

function refreshStatus() {
  const t = app.t;
  const checks = checksOf(app.current.model, currentId());
  const byStep = STEPS.map(() => []);
  for (const item of checks) byStep[stepOf(item)].push(item);
  app.el.pills.forEach((pill, index) => {
    const count = byStep[index].length;
    pill.querySelector('.count').textContent = count ? t('checks.pill', { n: count }) : '';
    pill.classList.toggle('has-checks', count > 0);
  });
  const mine = byStep[app.step];
  // A key named in a message is said with its words (checkname.<key>), never as the sheet writes it.
  const plain = (args) => ({ ...args, name: t(`checkname.${args.name}`, {}, args.name ?? '') });
  app.el.checks.replaceChildren(...(mine.length ? [h('div', { class: 'checkbox-list' },
    h('b', { text: t('checks.title', { n: mine.length }) }),
    h('ul', {}, mine.map((item) => h('li', { text: t(item.key, plain(item.args)) }))),
    h('small', { class: 'muted', text: t('checks.judge') }))] : []));
  app.el.dirty.textContent = app.current.dirty ? t('editor.unsaved') : t('editor.saved');
  app.el.dirty.className = app.current.dirty ? 'dirty on' : 'dirty';
  if (app.preview) app.el.preview.textContent = sheet.serialize(app.current.model);
}

function renderStep() {
  const step = STEPS[app.step];
  app.el.body.replaceChildren(step.render(stepContext()));
  const shown = shownSteps();
  app.el.pills.forEach((pill, index) => {
    pill.hidden = !shown.includes(index);
    pill.classList.toggle('on', index === app.step);
    pill.setAttribute('aria-current', index === app.step ? 'step' : 'false');
  });
  app.el.allSteps.hidden = shown.length === STEPS.length;
  const at = shown.indexOf(app.step);
  app.el.prev.disabled = at <= 0;
  app.el.next.hidden = at === shown.length - 1;
  app.el.finish.hidden = at !== shown.length - 1;
  refreshStatus();
}

function goStep(index) {
  app.step = Math.max(0, Math.min(STEPS.length - 1, index));
  renderStep();
  app.el.body.querySelector('input, textarea, select, button')?.focus({ preventScroll: true });
}

// The shown step before or after the open one.
function moveStep(delta) {
  const shown = shownSteps();
  goStep(shown[shown.indexOf(app.step) + delta] ?? app.step);
}

function actionButtons(status) {
  if (app.current.isNew) return [];
  return (ACTIONS_BY_STATUS[status] ?? []).map((name) => {
    const action = ACTIONS[name];
    return button(action.danger ? 'danger' : 'neutral', { onClick: async () => {
      const name = entryOf(app.current.id)?.name || app.current.id;   // the display name, the id when it has none
      const yes = await confirmBar(app.el.notice, app.t, { message: app.t(action.ask, { name }),
        yes: app.t(`${action.ask}_yes`), danger: action.danger });
      if (!yes) return;
      const result = await action.run(app.api, app.current.id);
      toast(codeText(result), !result.ok);
      if (!result.ok) return;
      app.current.dirty = false;
      const id = app.current.id;
      await refreshVoices();
      if (entryOf(id)) await openVoice(id); else { app.current = null; showWelcome(); await refreshVoices(); }
    } }, app.t(`editor.${action.label}`));
  });
}

function renderEditor() {
  const t = app.t;
  const current = app.current;
  const entry = current.isNew ? null : entryOf(current.id);
  const status = current.isNew ? 'custom' : voiceStatus(entry);
  app.el.notice = h('div', { class: 'notice-host' });
  if (current.empty) {
    clear(app.el.main).append(h('article', { class: 'welcome' },
      h('h2', { text: entry?.name || current.id }),
      h('p', { text: t('editor.removed_help') }), app.el.notice,
      h('div', { class: 'btns' }, actionButtons(status))));
    return;
  }
  app.el.dirty = h('span', { class: 'dirty' });
  app.el.verdict = h('div', { class: 'verdict-host' });
  app.el.checks = h('div', { class: 'checks-host' });
  app.el.body = h('div', { class: 'step-body' });
  app.el.preview = h('pre', { class: 'sheet-preview', 'aria-label': t('editor.preview') });
  app.el.pills = STEPS.map((step, index) => h('button', { type: 'button', class: 'pill', 'data-step': step.id,
    onClick: () => goStep(index) },
  h('span', { class: 'n', 'aria-hidden': 'true', text: t(`step.${step.id}.icon`) }), t(`step.${step.id}`), h('span', { class: 'count' })));
  app.el.allSteps = button('neutral', { id: 'all-steps', class: 'pill more-steps', title: t('editor.all_steps_help'),
    onClick: () => { app.ui.all_steps = true; renderStep(); } }, t('editor.all_steps'));
  app.el.prev = button('neutral', { id: 'step-prev', onClick: () => moveStep(-1) }, t('editor.prev'));
  app.el.next = button('primary', { id: 'step-next', onClick: () => moveStep(1) }, t('editor.next'));
  app.el.finish = button('primary', { id: 'step-finish', onClick: save }, t('editor.save'));
  // Rare actions in the "..." menu (S13): a copy of the voice's file, the text the game reads.
  const exportLink = current.isNew ? null : h('a', { role: 'menuitem', class: 'menu-item', href: app.api.exportUrl(current.id),
    download: `${current.id}.txt` }, t('editor.export'));
  const previewToggle = button('neutral', { class: 'menu-item', 'aria-pressed': String(app.preview), onClick: () => {
    app.preview = !app.preview;
    renderEditor();
  } }, app.preview ? t('editor.preview_hide') : t('editor.preview'));
  const menu = h('details', { class: 'more-menu' }, h('summary', { 'aria-label': t('editor.more'), title: t('editor.more') }, '…'),
    h('div', { class: 'menu', role: 'menu' }, exportLink, previewToggle));
  const tryToggle = button('neutral', { id: 'try-open', 'aria-pressed': String(app.chat.open),
    title: app.ai.available ? t('ai.try_help') : t('ai.unavailable'), onClick: () => {
      app.chat.open = !app.chat.open;
      renderEditor();
    } }, t('ai.try_title'));
  const side = app.preview || app.chat.open;
  clear(app.el.main).append(
    h('div', { class: 'toolbar' },
      h('div', { class: 'title' },
        h('h2', { text: sheet.value(current.model.head, 'name') || t('editor.untitled'), title: current.id }),
        h('span', { class: `badge ${status}`, title: current.isNew ? null : t(`status.${status}.help`),
          text: current.isNew ? t('status.new') : t(`status.${status}`) }),
        app.el.dirty),
      h('div', { class: 'btns' },
        button('primary', { id: 'save', onClick: save }, t('editor.save')),
        tryToggle, actionButtons(status), menu)),
    app.el.verdict,
    app.el.notice,
    h('nav', { class: 'steps', 'aria-label': t('editor.steps') }, app.el.pills, app.el.allSteps),
    app.el.checks,
    h('div', { class: side ? 'work split' : 'work' },
      h('article', { class: 'step-col' }, app.el.body,
        h('div', { class: 'btns nav' }, app.el.prev, app.el.next, app.el.finish)),
      side && h('aside', { class: 'preview-col' },
        app.chat.open && tryDrawer({ ai: app.ai, t, voiceId: currentId(), chat: app.chat,
          sheetText, onClose: () => { app.chat.open = false; renderEditor(); } }),
        app.preview && h('div', { class: 'side-h', text: t('editor.preview') }), app.preview && app.el.preview)));
  renderStep();
  renderVerdictBanner();
}

async function save() {
  const current = app.current;
  // A voice of the same id made meanwhile (another tab): the new one takes the next free id.
  if (current.isNew && entryOf(currentId())) sheet.setValue(current.model.head, 'id', voice.voiceId(currentId(), takenIds()));
  const id = currentId();
  const text = sheet.serialize(current.model);
  const result = await app.api.save(id, text);
  toast(codeText(result), !result.ok);
  if (!result.ok) return;
  const pending = checksOf(current.model, id).length;
  if (pending) toast(`${codeText(result)} ${app.t('checks.saved_anyway', { n: pending })}`);
  Object.assign(current, { id, isNew: false, dirty: false, saved: text });
  refreshVerdicts();
  await refreshVoices();
  renderEditor();
}

// --- import ---------------------------------------------------------------------------------------------------------
async function importFile(file) {
  if (!file) return;
  if (!(await leaveCurrent())) return;
  const text = await file.text();
  let result = await app.api.importSheet(file.name, text);
  if (!result.ok && result.code === 'voice_exists') {
    // X15: one button, the next free id made from the file's name.
    const yes = await confirmBar(app.el.notice, app.t, { message: app.t('import.exists', { name: file.name }),
      yes: app.t('import.as_new') });
    if (!yes) return;
    result = await app.api.importSheet(file.name, text, voice.voiceId(file.name.replace(/\.txt$/i, ''), takenIds()));
  }
  toast(codeText(result), !result.ok);
  if (result.ok) {
    if (app.current) app.current.dirty = false;
    await openVoice(result.id);
  }
}

function wireImport() {
  const input = h('input', { type: 'file', accept: '.txt,text/plain', hidden: true,
    onChange: (e) => { importFile(e.target.files[0]); e.target.value = ''; } });
  app.el.importButton.addEventListener('click', () => input.click());
  document.body.append(input);
  let depth = 0;
  const zone = app.el.dropzone;
  const hasFile = (e) => [...(e.dataTransfer?.types ?? [])].includes('Files');
  window.addEventListener('dragenter', (e) => { if (hasFile(e)) { depth += 1; zone.hidden = false; } });
  window.addEventListener('dragleave', () => { depth = Math.max(0, depth - 1); if (!depth) zone.hidden = true; });
  window.addEventListener('dragover', (e) => { if (hasFile(e)) e.preventDefault(); });
  window.addEventListener('drop', (e) => {
    if (!hasFile(e)) return;
    e.preventDefault();
    depth = 0;
    zone.hidden = true;
    importFile(e.dataTransfer.files[0]);
  });
}

// --- shell ----------------------------------------------------------------------------------------------------------
function showWelcome() {
  app.el.notice = h('div', { class: 'notice-host' });
  clear(app.el.main).append(h('article', { class: 'welcome' },
    h('h2', { text: app.t('welcome.title') }),
    h('p', { text: app.t('welcome.text') }),
    h('ol', { class: 'howto' }, ['welcome.step1', 'welcome.step2', 'welcome.step3'].map((k) => h('li', {},
      h('span', { class: 'howto-icon', 'aria-hidden': 'true', text: app.t(`${k}.icon`) }), h('span', { text: app.t(k) })))),
    app.el.notice,
    h('div', { class: 'btns start' }, button('primary', { onClick: showNewVoice }, app.t('voices.new')))));
}

// Views next to each other, one tab each (app.views, in tab order): the dashboard of the voices (E24-T05), the voice
// editor and the live journal (E22-T10). The Voices and Places tabs list their things on the left (masterdetail.js),
// the Dashboard and the Journal take the whole width; opening a voice comes back to the editor. A view may start when
// shown (read again, poll) and stop when hidden.
function showView(view) {
  for (const [name, shown] of Object.entries(app.views)) {
    const on = name === view;
    shown.el.hidden = !on;
    if (on) shown.start?.(); else shown.stop?.();
  }
  app.el.tabs.forEach((tab) => tab.setAttribute('aria-selected', String(tab.dataset.view === view)));
}

function renderShell() {
  const t = app.t;
  document.title = t('app.title');
  app.el.importButton = button('neutral', { id: 'import', title: t('import.button_help') }, t('import.button'));
  app.el.side = h('aside', { class: 'side' });
  app.el.main = h('main', { class: 'main', id: 'main' });
  // A voice opened from the dashboard or a place: the editor is shown first, where "leave without saving?" is asked if
  // needed.
  const openInEditor = (id) => { showView('voices'); return openVoice(id); };
  const dashboard = createDashboard({ api: app.api, t, catalog: app.catalog, open: openInEditor,
    verdicts: () => app.verdicts });
  const journal = createJournal({ api: app.api, t, voiceIds: () => app.voices.map((v) => v.id) });
  const places = createPlacesView({ api: app.api, t, catalog: app.catalog, ai: app.ai, toast, store: app.places,
    open: openInEditor, current: () => (app.current && !app.current.empty ? { id: app.current.id,
      name: sheet.value(app.current.model.head, 'name') || app.current.id, model: app.current.model } : null) });
  const voices = masterDetail({ id: 'voices', label: t('tab.voices'), side: app.el.side, detail: app.el.main });
  app.views = { dashboard, places, voices: { el: voices }, journal };
  for (const view of [dashboard, journal]) view.el.classList.add('main');
  app.el.tabs = Object.keys(app.views).map((view) => h('button', { type: 'button', role: 'tab', class: 'tab', id: `tab-${view}`,
    'data-view': view, 'aria-selected': 'false', onClick: () => showView(view) }, t(`tab.${view}`)));
  app.el.toast = h('div', { class: 'toast', role: 'status', 'aria-live': 'polite',
    onClick: () => { clearTimeout(toastTimer); app.el.toast.className = 'toast'; } });
  app.el.dropzone = h('div', { class: 'dropzone', hidden: true }, h('p', { text: t('import.drop') }));
  document.body.replaceChildren(
    h('a', { class: 'skip', href: '#main' }, t('app.skip')),
    h('header', { class: 'top' },
      h('div', { class: 'brand' }, h('span', { class: 'logo', 'aria-hidden': 'true' }, '◉'),
        h('div', {}, h('h1', { text: t('app.title') }), h('p', { class: 'sub', text: t('app.subtitle') }))),
      h('div', { class: 'tabs', role: 'tablist', 'aria-label': t('app.title') }, app.el.tabs),
      h('div', { class: 'btns' }, app.el.importButton,
        app.login && button('neutral', { id: 'logout', onClick: logout }, t('app.logout')))),
    h('div', { class: 'layout' }, Object.values(app.views).map((view) => view.el)),
    app.el.toast, app.el.dropzone);
}

async function boot() {
  app.t = await loadI18n(navigator.language);
  document.documentElement.lang = app.t.lang;
  if ((await refreshAi()).status === 401) return;   // E22-T15: session gone, the login page opens
  app.catalog = await loadCatalog();
  Object.assign(app.ai, { api: app.api, toast });
  app.places = createPlaceStore(app.api, app.catalog);
  await app.places.load();
  // A place made or removed: the lists and checks of the voice open in the editor follow.
  app.places.onChange(() => { if (app.current && !app.current.empty && app.el.body?.isConnected) renderStep(); });
  renderShell();
  wireImport();
  showWelcome();
  showView('dashboard');
  await refreshVoices();
  pollVerdicts();
  window.addEventListener('beforeunload', (e) => { if (app.current?.dirty) e.preventDefault(); });
}

boot().catch((err) => {
  document.body.textContent = `Voice workshop failed to start: ${err.message}`;
  console.error(err);
});
