// E22-T06 (ADR atelier-voix D04): the bridge's AI helps to write the voice. Three pieces, each given only what it uses:
// - personalityPanel: "Write it with the AI" in the step "personality" (description -> English [prompt]);
// - proposeButton: "Suggest" next to a text the author types (name, description, place, mission story, call, note
//   line...): the bridge's AI fills it from the whole unsaved sheet and the details of that field (E24-T04);
// - tryDrawer: "Try the voice", a chat over the CURRENT UNSAVED sheet text (the bridge builds the prompt as in game).
// Without AI configured (`ai.available` false) every button is greyed with a tooltip saying to ask the adult who runs
// the workshop (E24-T02; how to configure it is in the wiki).

import { confirmBar } from './dialogs.js';
import { clear, h } from './dom.js';
import { FREQUENCY_MARK, freqToScreen, freqToSheet } from './values.js';
import { button, removeButton } from './widgets.js';

// Details of a field sent to the AI (POST /api/ai/suggest): flat, at most this many keys, each value this long.
const MAX_DETAILS = 16;
const MAX_DETAIL_CHARS = 600;
const DETAIL_KEY_RE = /^[a-z_]{1,32}$/;

function codeText(t, result) {
  return t(`code.${result.code}`, {}, result.message || result.code);
}

// AI button: greyed with the configuration tooltip when no AI is configured.
export function aiButton(ai, t, label, onClick, attrs = {}) {
  return button('ai', { ...attrs, disabled: !ai.available,
    title: ai.available ? (attrs.title ?? null) : t('ai.unavailable'), onClick }, label);
}

async function busy(el, run) {
  const label = el.textContent;
  el.disabled = true;
  el.setAttribute('aria-busy', 'true');
  try { return await run(); } finally { el.disabled = false; el.removeAttribute('aria-busy'); el.textContent = label; }
}

// --- personality ----------------------------------------------------------------------------------------------------
// ctx: { ai, t, voiceId, name, description, sheetText(), currentPrompt(), usePrompt(text) }
export function personalityPanel(ctx) {
  const { ai, t } = ctx;
  const host = h('div', { class: 'ai-panel', hidden: true, id: 'ai-personality' });
  const open = aiButton(ai, t, t('personality.ai'), (e) => {
    host.hidden = !host.hidden;
    e.currentTarget.setAttribute('aria-expanded', String(!host.hidden));
    if (!host.hidden) host.querySelector('textarea')?.focus();
  }, { id: 'ai-personality-open', 'aria-expanded': 'false', 'aria-controls': 'ai-personality' });
  const description = h('textarea', { rows: 4, class: 'ai-description', value: ctx.description,
    'aria-label': t('ai.describe'), placeholder: t('ai.describe_placeholder') });
  const result = h('pre', { class: 'ai-result', hidden: true, 'aria-live': 'polite' });
  const status = h('p', { class: 'help', 'aria-live': 'polite' });
  const ask = h('div', { class: 'notice-host' });
  let proposal = '';
  const use = button('primary', { hidden: true, id: 'ai-personality-use', onClick: async () => {
    if (ctx.currentPrompt().trim()) {
      const yes = await confirmBar(ask, t, { message: t('ai.replace_confirm'), yes: t('ai.use'), danger: true });
      if (!yes) return;
    }
    ctx.usePrompt(proposal);
  } }, t('ai.use'));
  const generate = button('neutral', { id: 'ai-personality-generate', onClick: () => busy(generate, async () => {
    if (!description.value.trim()) { status.textContent = t('ai.describe_first'); description.focus(); return; }
    generate.textContent = t('ai.working');
    status.textContent = '';
    const answer = await ai.api.aiPersonality({ voiceId: ctx.voiceId, name: ctx.name, description: description.value });
    if (!answer.ok) { status.textContent = codeText(t, answer); return; }
    proposal = answer.prompt;
    result.textContent = proposal;
    result.hidden = false;
    use.hidden = false;
  }) }, t('ai.generate'));
  // The few sentences themselves can be proposed by the AI from the rest of the sheet (E24-T04).
  const idea = proposeButton({ ai, t, field: 'persona_idea', voiceId: ctx.voiceId, sheetText: ctx.sheetText,
    current: () => description.value, apply: (text) => fillField(description, text) });
  host.append(h('p', { class: 'help', text: t('ai.describe_help') }), description,
    h('div', { class: 'btns' }, generate, idea, use), status, result, ask);
  return { button: open, panel: host };
}

// --- suggest a text -------------------------------------------------------------------------------------------------
// Details as the server takes them: string values cut to their limit, empty ones and bad keys left out.
export function suggestDetails(details) {
  return Object.fromEntries(Object.entries(details ?? {})
    .filter(([key, value]) => DETAIL_KEY_RE.test(key) && value !== null && value !== undefined && String(value).trim() !== '')
    .slice(0, MAX_DETAILS)
    .map(([key, value]) => [key, String(value).slice(0, MAX_DETAIL_CHARS)]));
}

// Writes a proposal into a field as if typed: the field's own handler stores it in the sheet (`event`: the event it
// listens to). A frequency field (freqText) gets the sheet's mark shown as the word (`freqWord`).
export function fillField(input, text, { event = 'input', freqWord = null } = {}) {
  input.value = freqWord ? freqToScreen(text, freqWord) : text;
  input.dispatchEvent(new Event(event, { bubbles: true }));
}

// ctx: { ai, t, field, voiceId, sheetText(), current(), details(), apply(text), pageLanguage }. Each click sends the
// text in the field now, so the AI proposes something else.
export function proposeButton(ctx) {
  const { ai, t } = ctx;
  const propose = aiButton(ai, t, t('ai.propose'), () => busy(propose, async () => {
    propose.textContent = t('ai.working');
    const answer = await ai.api.aiSuggest({ field: ctx.field, voiceId: ctx.voiceId || null,
      sheetText: ctx.sheetText?.() ?? '', pageLanguage: ctx.pageLanguage ?? t.lang, current: ctx.current?.() ?? '',
      details: suggestDetails(ctx.details?.()) });
    if (!answer.ok) { ai.toast(codeText(t, answer), true); return; }
    ctx.apply(answer.text);
  }), { title: t('ai.propose_help'), class: 'propose', 'data-field': ctx.field });
  return propose;
}

// The frequency mark as the AI writes it (the server turns it into the sheet's mark).
const AI_FREQUENCY = '{frequency}';

// proposeButton of a typed field of a step: the AI, the voice and its unsaved sheet taken from the step's context; the
// field's text sent as it is now and the proposal written into it (`event`, `freqWord`: see fillField).
export function inputPropose(ctx, field, input, { details = () => ({}), event = 'input', freqWord = null } = {}) {
  const current = () => (freqWord
    ? freqToSheet(input.value, freqWord).split(FREQUENCY_MARK).join(AI_FREQUENCY) : input.value);
  return proposeButton({ ai: ctx.ai, t: ctx.t, voiceId: ctx.voiceId, sheetText: ctx.sheetText, field, current, details,
    apply: (text) => fillField(input, text, { event, freqWord }) });
}

// A typed field and its "Suggest" button right after it, on the same line.
export function withPropose(ctx, field, input, options = {}) {
  return h('div', { class: 'inline grow' }, input, inputPropose(ctx, field, input, options));
}

// What the AI is told of a shared place when it proposes its name (E25-T03): a spot or an area in words, its square or
// its corners when known, and the voices that use it.
export function placeDetails(t, place, usedBy = []) {
  const known = (...values) => values.every((v) => String(v ?? '').trim() !== '');
  const trim = (v) => String(v).trim();
  const at = place.at ?? {};
  const area = place.area ?? {};
  const zone = place.kind === 'zone';
  return {
    where: t(`places.kind.${zone ? 'zone' : 'point'}`),
    map_square: !zone && known(at.x, at.y) ? [at.x, at.y, at.z || '0'].map(trim).join(',') : null,
    map_area: zone && known(area.x1, area.y1, area.x2, area.y2)
      ? `${trim(area.x1)},${trim(area.y1)} - ${trim(area.x2)},${trim(area.y2)}, floor ${trim(place.z || '0')}` : null,
    used_by: usedBy.join(', ') || null,
  };
}

// A text of the sheet as the AI reads it in the details: the frequency mark as the AI writes it.
export const forAi = (text) => String(text ?? '').split(FREQUENCY_MARK).join(AI_FREQUENCY);

// --- test conversation ----------------------------------------------------------------------------------------------
// ctx: { ai, t, voiceId, sheetText(), chat: {messages: [{role, content}]}, onClose() }
export function tryDrawer(ctx) {
  const { ai, t, chat } = ctx;
  const list = h('div', { class: 'chat-list', 'aria-live': 'polite', id: 'try-list' });
  const input = h('input', { type: 'text', id: 'try-input', autocomplete: 'off', 'aria-label': t('ai.try_input'),
    placeholder: t('ai.try_placeholder'), disabled: !ai.available });
  const status = h('p', { class: 'help', 'aria-live': 'polite' });
  const draw = () => {
    clear(list).append(...(chat.messages.length ? chat.messages.map((m) => h('div', { class: `msg ${m.role}` },
      h('small', { text: m.role === 'user' ? t('ai.try_you') : t('ai.try_voice_name') }), h('p', { text: m.content })))
      : [h('p', { class: 'muted', text: ai.available ? t('ai.try_empty') : t('ai.unavailable') })]));
    list.scrollTop = list.scrollHeight;
  };
  const send = button('primary', { id: 'try-send', disabled: !ai.available,
    title: ai.available ? null : t('ai.unavailable'), onClick: () => busy(send, async () => {
      const text = input.value.trim();
      if (!text) return;
      const history = chat.messages.slice();
      chat.messages.push({ role: 'user', content: text });
      input.value = '';
      status.textContent = t('ai.working');
      draw();
      const answer = await ai.api.aiTry({ voiceId: ctx.voiceId, sheetText: ctx.sheetText(), history, text });
      status.textContent = '';
      if (!answer.ok) {
        chat.messages.pop();
        input.value = text;
        status.textContent = codeText(t, answer);
        draw();
        return;
      }
      chat.messages.push({ role: 'assistant', content: answer.lines.join(' ') });
      draw();
      input.focus();
    }) }, '➤');
  send.setAttribute('aria-label', t('ai.try_send'));
  send.title = ai.available ? t('ai.try_send') : t('ai.unavailable');
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') send.click(); });
  const reset = button('neutral', { id: 'try-reset', onClick: () => {
    chat.messages.length = 0;
    status.textContent = '';
    draw();
  } }, t('ai.try_reset'));
  draw();
  return h('section', { class: 'try-drawer', 'aria-label': t('ai.try_title') },
    h('div', { class: 'side-h' }, h('span', { text: t('ai.try_title') }),
      removeButton(t, ctx.onClose, t('ai.try_close'))),
    h('p', { class: 'help', text: t('ai.try_help') }),
    list, status,
    h('div', { class: 'inline grow' }, input, send),
    h('div', { class: 'btns' }, reset));
}
