// Login page of the voice workshop in network mode (E22-T15, ADR atelier-voix D11). Served without a session with only
// what it loads (dom.js, i18n.js, the strings and the styles): one password field, POST /api/login, then the workshop.
// A refusal is shown in the page language: wrong password, or the seconds to wait after too many failures.

import { h } from './dom.js';
import { loadI18n } from './i18n.js';

async function logIn(password) {
  try {
    const response = await fetch('/api/login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password }),
      cache: 'no-store',
    });
    return await response.json();
  } catch (err) {
    return { ok: false, code: 'offline', message: String(err) };
  }
}

function refusal(t, result) {
  if (result.code === 'login_locked') return t('login.locked', { seconds: result.retryAfter ?? '?' });
  return t(`code.${result.code}`, {}, result.message || result.code);
}

async function boot() {
  const t = await loadI18n(navigator.language);
  document.documentElement.lang = t.lang;
  document.title = t('app.title');
  const field = h('input', { type: 'password', id: 'password', name: 'password', autocomplete: 'current-password',
    required: true, autofocus: true });
  const message = h('p', { class: 'login-message', role: 'alert', 'aria-live': 'assertive' });
  const submit = h('button', { type: 'submit', id: 'login-submit' }, t('login.submit'));
  const form = h('form', { class: 'login-card', onSubmit: async (event) => {
    event.preventDefault();
    submit.disabled = true;
    message.textContent = '';
    const result = await logIn(field.value);
    if (result.ok) { window.location.assign('/'); return; }
    submit.disabled = false;
    message.textContent = refusal(t, result);
    field.select();
  } },
  h('div', { class: 'brand' }, h('span', { class: 'logo', 'aria-hidden': 'true' }, '◉'),
    h('div', {}, h('h1', { text: t('app.title') }), h('p', { class: 'sub', text: t('app.subtitle') }))),
  h('h2', { text: t('login.heading') }),
  h('p', { class: 'help', text: t('login.intro') }),
  h('label', { for: 'password' }, t('login.password'), field),
  message,
  submit);
  document.body.replaceChildren(h('main', { class: 'login' }, form));
  field.focus();
}

boot().catch((err) => {
  document.body.textContent = `Voice workshop failed to start: ${err.message}`;
  console.error(err);
});
