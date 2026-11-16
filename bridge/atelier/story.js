// Story state of a mission (sets_state=, E24-T02 user decision): the author writes a short sentence ("She went back to
// her clinic"); the page makes the name the game stores from it (a deterministic slug, [a-z][a-z0-9_], 32 at most, as
// RS_Persona and the bridge read it) and never shows that name. The bridge only gives the AI the name of the state
// (radio_bridge.story_prompt: "your sheet tells what it means"), so the sentence goes where the AI reads the sheet: one
// line of the personality text ([prompt]) per state, "Story state: when your story state is <name>, <sentence>" (the
// form of the wiki's examples). The line of a state is written when a mission sets it and removed when no mission sets
// it any more. Two missions with the same sentence share one state; another sentence that makes the same name gets
// the next free name (<name>_2...). Pure module.

import * as sheet from './sheet.js';
import { slug } from './voice.js';

const MAX_NAME = 32;
const LINE_START = 'Story state: when your story state is ';
const LINE_RE = /^Story state: when your story state is ([a-z][a-z0-9_]*), (.*)$/;

export const slugOf = (sentence) => slug(sentence, 'state', MAX_NAME);

// {name: sentence} of the story lines of a personality text.
export function lines(prompt) {
  const out = {};
  for (const line of String(prompt ?? '').split('\n')) {
    const match = LINE_RE.exec(line.trim());
    if (match) out[match[1]] = match[2];
  }
  return out;
}

// The sentence of a mission's state: its line in the personality text, else the words of a name written by hand.
export function sentence(model, mission) {
  const name = sheet.value(mission, 'sets_state');
  if (!name) return '';
  return lines(sheet.promptText(model))[name] ?? name.replace(/_/g, ' ');
}

const linesWithout = (prompt, name) => String(prompt ?? '').split('\n')
  .filter((line) => LINE_RE.exec(line.trim())?.[1] !== name);

// Personality text with the line of `name` set to `text` (appended at the end), or removed when `text` is null.
function writeLine(model, name, text) {
  const kept = linesWithout(sheet.promptText(model), name);
  while (kept.length && kept[kept.length - 1].trim() === '') kept.pop();
  if (text !== null) kept.push(...(kept.length && !LINE_RE.test(kept[kept.length - 1].trim()) ? [''] : []), `${LINE_START}${name}, ${text}`);
  sheet.setPromptText(model, kept.join('\n'));
}

// A new personality text (written by the AI) with the story lines of the old one it lacks, at its end.
export function carry(oldPrompt, newPrompt) {
  const have = lines(newPrompt);
  const kept = Object.entries(lines(oldPrompt)).filter(([name]) => !(name in have))
    .map(([name, text]) => `${LINE_START}${name}, ${text}`);
  const base = String(newPrompt ?? '').replace(/\s+$/, '');
  return kept.length ? `${base}\n\n${kept.join('\n')}` : String(newPrompt ?? '');
}

// Sets the story state of `mission` from `text` (empty: no state). A state no other mission sets loses its line.
export function setStory(model, mission, text) {
  const words = String(text ?? '').replace(/\s+/g, ' ').trim();
  const old = sheet.value(mission, 'sets_state');
  const others = sheet.sectionsOf(model, 'mission').filter((m) => m !== mission).map((m) => sheet.value(m, 'sets_state'));
  const known = lines(sheet.promptText(model));
  let name = null;
  if (words) {
    name = Object.keys(known).find((n) => known[n] === words && others.includes(n)) ?? null;
    if (!name) {
      const base = slugOf(words);
      const taken = (n) => others.includes(n) || (n in known && n !== old);
      name = base;
      for (let i = 2; taken(name); i += 1) name = `${base.slice(0, MAX_NAME - String(i).length - 1)}_${i}`;
    }
  }
  sheet.setValue(mission, 'sets_state', name);
  if (old && old !== name && !others.includes(old)) writeLine(model, old, null);
  if (name) writeLine(model, name, words);
}
