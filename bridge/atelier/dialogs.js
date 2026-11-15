// In-page questions (never alert/confirm/prompt): a bar shown in `host` until the player answers.

import { clear, h } from './dom.js';
import { button } from './widgets.js';

export function confirmBar(host, t, { message, yes, danger = false }) {
  return new Promise((resolve) => {
    const done = (answer) => { clear(host); resolve(answer); };
    const yesButton = button(danger ? 'danger' : 'primary', { onClick: () => done(true) }, yes);
    clear(host).append(h('div', { class: danger ? 'notice danger' : 'notice', role: 'alertdialog', 'aria-label': message },
      h('p', { text: message }),
      h('div', { class: 'btns' },
        button('neutral', { onClick: () => done(false) }, t('dialog.cancel')), yesButton)));
    yesButton.focus();
  });
}

export function askBar(host, t, { message, label, value = '', ok, check = () => null }) {
  return new Promise((resolve) => {
    const done = (answer) => { clear(host); resolve(answer); };
    const error = h('p', { class: 'warnline', 'aria-live': 'polite' });
    const input = h('input', { type: 'text', value, 'aria-label': label, spellcheck: 'false', autocomplete: 'off' });
    const submit = () => {
      const problem = check(input.value.trim());
      if (problem) { error.textContent = problem; input.focus(); return; }
      done(input.value.trim());
    };
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); if (e.key === 'Escape') done(null); });
    clear(host).append(h('div', { class: 'notice', role: 'dialog', 'aria-label': message },
      h('p', { text: message }),
      h('label', { class: 'inline grow' }, h('span', { text: label }), input),
      error,
      h('div', { class: 'btns' },
        button('neutral', { onClick: () => done(null) }, t('dialog.cancel')),
        button('primary', { onClick: submit }, ok))));
    input.focus();
    input.select();
  });
}
