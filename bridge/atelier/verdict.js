// The game's verdict on the open voice (E22-T04, ADR atelier-voix D03): a banner with the reason in plain words, the
// game's own English reason, and a button to the step that owns the refused line. The page computes that step; this
// module only shows it. Plain words come from a table of the game's fixed messages (persona-format.md, "Erreurs"):
// a message not in the table gets a general sentence, the raw reason is always shown.

import { h } from './dom.js';
import { button } from './widgets.js';

const PLAIN = [
  { re: /^unknown key '([^']+)'/, key: 'verdict.why.unknown_key' },
  { re: /^duplicate key '([^']+)'/, key: 'verdict.why.duplicate_key' },
  { re: /^missing key '([^']+)'/, key: 'verdict.why.missing_key' },
  { re: /^empty value for key '([^']+)'/, key: 'verdict.why.empty_value' },
  { re: /^(?:bad frequency|frequency |duplicate frequency)/, key: 'verdict.why.frequency' },
  { re: /^unknown section '([^']+)'/, key: 'verdict.why.unknown_section' },
  { re: /^unknown (?:place|mission|category) '([^']+)'/, key: 'verdict.why.unknown_ref' },
  { re: /^unknown mission type '([^']+)'/, key: 'verdict.why.mission_type' },
  { re: /^(?:missing \[prompt\]|empty prompt)/, key: 'verdict.why.prompt' },
  { re: /(?:invalid UTF-8|byte order mark)/, key: 'verdict.why.encoding' },
];

export function plainReason(t, reason) {
  const text = String(reason ?? '');
  for (const { re, key } of PLAIN) {
    const match = re.exec(text);
    if (match) return t(key, { name: match[1] ?? '' });
  }
  return t('verdict.why.other');
}

// verdict: {state, line, reason} of GET /api/verdicts; target: {step, place, go} or null. Null when there is nothing
// to say (no verdict, voice accepted or removed by the game).
export function renderVerdict(verdict, { t, target }) {
  if (verdict?.state === 'changed') {
    return h('div', { class: 'verdict waiting', role: 'status' }, h('p', { text: t('verdict.changed') }));
  }
  if (verdict?.state !== 'refused') return null;
  const title = verdict.line ? t('verdict.title', { line: verdict.line }) : t('verdict.title_noline');
  return h('div', { class: 'verdict', role: 'alert' },
    h('p', { class: 'verdict-title' }, h('span', { class: 'gamebad', 'aria-hidden': 'true' }), h('b', { text: title })),
    h('p', { text: plainReason(t, verdict.reason) }),
    h('p', { class: 'verdict-raw' }, h('small', { text: t('verdict.raw') }), ' ', h('code', { text: verdict.reason ?? '' })),
    h('p', { class: 'help', text: t('verdict.silent') }),
    target && h('div', { class: 'btns' },
      button('primary', { id: 'verdict-go', onClick: target.go },
        t('verdict.go', { step: target.step })),
      target.place && h('code', { text: target.place })));
}
