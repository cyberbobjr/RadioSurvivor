// E22-T06 (ADR atelier-voix D04): the bridge's AI helps to write the voice. Three pieces, each given only what it uses:
// - personalityPanel: "Write it with the AI" in the step "personality" (description -> English [prompt]);
// - suggestButton: "Suggest" next to the story of a mission card (one sentence);
// - tryDrawer: "Try the voice", a chat over the CURRENT UNSAVED sheet text (the bridge builds the prompt as in game).
// Without AI configured (`ai.available` false) every button is greyed with a tooltip saying to ask the adult who runs
// the workshop (E24-T02; how to configure it is in the wiki).

import { confirmBar } from './dialogs.js';
import { clear, h } from './dom.js';
import { button, removeButton } from './widgets.js';

const STORY_MAX = 200;

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
// ctx: { ai, t, voiceId, name, description, currentPrompt(), usePrompt(text) }
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
  host.append(h('p', { class: 'help', text: t('ai.describe_help') }), description,
    h('div', { class: 'btns' }, generate, use), status, result, ask);
  return { button: open, panel: host };
}

// --- mission story --------------------------------------------------------------------------------------------------
// ctx: { ai, t, voiceId, missionType, voiceText, context, setStory(text) }
export function suggestButton(ctx) {
  const { ai, t } = ctx;
  const suggest = aiButton(ai, t, t('ai.suggest'), () => busy(suggest, async () => {
    suggest.textContent = t('ai.working');
    const answer = await ai.api.aiStory({ voiceId: ctx.voiceId, missionType: ctx.missionType, voiceText: ctx.voiceText,
      context: ctx.context });
    if (!answer.ok) { ai.toast(codeText(t, answer), true); return; }
    ctx.setStory(answer.story.slice(0, STORY_MAX));
  }), { title: t('ai.suggest_help') });
  return suggest;
}

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
