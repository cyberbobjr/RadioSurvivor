// Help of every setting (E22-T11): a small "?" button next to a label or a choice opens a popover on hover, on keyboard
// focus and on click. Texts are data in i18n/<lang>.json, one topic per setting, its key derived from the catalogue
// names (help.head.<key>, help.<section>.<key>.<value>, help.mission_type.<type>, help.reward.<kind>...):
// <topic>.what (what it is for), .game (what the player lives in game), .example, .tip; the list of choices is built
// from the topics of the choices themselves. A topic without its .what line shows no button.

import { h } from './dom.js';

const POPOVER_ID = 'help-pop';
const MARGIN = 8;
const CLOSE_DELAY_MS = 150;

// First topic of `topics` (a key prefix or a list of them, most precise first) that has a .what line, else null.
export function resolveTopic(t, topics) {
  return [topics].flat().find((topic) => topic && t.has(`${topic}.what`)) ?? null;
}

// One line of a topic (its .what), or '' when it has none: the help of the selected value of a select.
export function helpLine(t, topics) {
  const topic = resolveTopic(t, topics);
  return topic ? t(`${topic}.what`) : '';
}

function content(t, topic, { label, choices, choicesTitle }) {
  const part = (name, title) => (t.has(`${topic}.${name}`)
    ? h('div', { class: `hp-${name}` }, title && h('b', { text: title }), h('p', { text: t(`${topic}.${name}`) }))
    : null);
  const items = (choices ?? []).map((c) => ({ label: c.label, line: helpLine(t, c.topic) })).filter((c) => c.line);
  return [
    label && h('p', { class: 'hp-title', text: label }),
    part('what'),
    part('game', t('hint.game')),
    items.length > 0 && h('div', { class: 'hp-choices' }, h('b', { text: choicesTitle ?? t('hint.choices') }),
      h('ul', {}, items.map((c) => h('li', {}, h('b', { text: c.label }), ` : ${c.line}`)))),
    part('example', t('hint.example')),
    part('tip', t('hint.tip')),
  ];
}

// The single popover of the page, placed next to the button that opened it.
const popover = {
  el: null,
  owner: null,
  pinned: false,
  timer: null,
  get() {
    if (!this.el) {
      this.el = h('div', { id: POPOVER_ID, class: 'help-pop', role: 'tooltip', hidden: true,
        onMouseenter: () => clearTimeout(this.timer), onMouseleave: () => this.closeSoon() });
      document.body.append(this.el);
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && this.owner) { const owner = this.owner; this.close(); owner.focus(); }
      });
      document.addEventListener('click', (e) => {
        if (this.owner && !this.owner.contains(e.target) && !this.el.contains(e.target)) this.close();
      });
      window.addEventListener('resize', () => this.place());
      window.addEventListener('scroll', () => this.place(), true);
    }
    return this.el;
  },
  open(button, children, pinned = false) {
    clearTimeout(this.timer);
    const el = this.get();
    // A modal dialog (item browser) is drawn above the whole page: the popover of one of its buttons goes inside it.
    const host = button.closest('dialog[open]') ?? document.body;
    if (el.parentElement !== host) host.append(el);
    if (this.owner && this.owner !== button) this.release();
    this.owner = button;
    this.pinned = pinned || (this.pinned && this.owner === button);
    el.replaceChildren(...children.filter(Boolean));
    el.hidden = false;
    button.setAttribute('aria-expanded', 'true');
    button.setAttribute('aria-describedby', POPOVER_ID);
    this.place();
  },
  release() {
    this.owner?.setAttribute('aria-expanded', 'false');
    this.owner?.removeAttribute('aria-describedby');
  },
  close() {
    clearTimeout(this.timer);
    if (!this.el) return;
    this.release();
    this.owner = null;
    this.pinned = false;
    this.el.hidden = true;
  },
  closeSoon() {
    if (this.pinned) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.close(), CLOSE_DELAY_MS);
  },
  // Below the button, or above it when there is no room; always inside the viewport.
  place() {
    if (!this.owner || !this.el || this.el.hidden) return;
    if (!this.owner.isConnected) { this.close(); return; }
    const anchor = this.owner.getBoundingClientRect();
    const width = Math.min(this.el.offsetWidth, window.innerWidth - 2 * MARGIN);
    const height = this.el.offsetHeight;
    const left = Math.max(MARGIN, Math.min(anchor.left, window.innerWidth - width - MARGIN));
    const below = anchor.bottom + 6;
    const top = below + height + MARGIN <= window.innerHeight || anchor.top < height + 2 * MARGIN
      ? Math.min(below, Math.max(MARGIN, window.innerHeight - height - MARGIN))
      : anchor.top - height - 6;
    this.el.style.left = `${left}px`;
    this.el.style.top = `${Math.max(MARGIN, top)}px`;
  },
};

// "?" button of a topic (key prefix or list of them), or null when no topic has help. Options: label (title of the
// popover and accessible name), choices [{label, topic}] listed with their one line, choicesTitle.
export function hint(t, topics, options = {}) {
  const topic = resolveTopic(t, topics);
  if (!topic) return null;
  const name = options.label ?? '';
  const show = (pinned) => popover.open(button, content(t, topic, options), pinned);
  const button = h('button', { type: 'button', class: 'hint', 'aria-label': t('hint.open', { name }),
    'aria-expanded': 'false', 'aria-controls': POPOVER_ID, 'data-topic': topic,
    onMouseenter: () => show(false), onMouseleave: () => popover.closeSoon(),
    onFocus: () => show(false), onBlur: () => popover.closeSoon(),
    onClick: (e) => {
      e.preventDefault();   // inside a <label>: never toggles its check box
      e.stopPropagation();
      if (popover.owner === button && popover.pinned) popover.close(); else show(true);
    } }, '?');
  return button;
}

// Help line under a select for its selected value (`prefix`.<value>), kept up to date when the value changes.
export function selectHelp(t, prefix, selectEl) {
  const line = h('p', { class: 'help choice-help', 'aria-live': 'polite' });
  const refresh = () => { line.textContent = selectEl.value ? helpLine(t, `${prefix}.${selectEl.value}`) : ''; };
  selectEl.addEventListener('change', refresh);
  refresh();
  return line;
}

// Choices of a closed list as {label, topic} for hint(): `prefix`.<value>.
export function choiceTopics(prefix, options) {
  return options.map((o) => ({ label: o.label, topic: `${prefix}.${o.value}` }));
}

// Option of a check box or radio list with its own "?" button (`prefix`.<value>).
export function withHint(t, prefix, option) {
  return { ...option, hint: hint(t, `${prefix}.${option.value}`, { label: option.label }) };
}
