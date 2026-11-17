"""Workshop AI requests (E22-T06, ADR atelier-voix D04): the bridge's LLM helps to write a voice sheet.

Three requests of the voice workshop page (bridge/atelier_server.py routes /api/ai/*):

    personality   an English [prompt] text in the structure of the delivered sheets, from a few sentences of the
                  author in any language (instructions: atelier_ai_templates.json, data, English);
    suggest       E24-T04: a proposal for one text field of the page (name, mission story, note line...), written
                  from the WHOLE unsaved sheet; one entry per field in the "suggest" section of the templates file;
    try_voice     one turn of a test conversation with the voice, its sheet read from the UNSAVED text of the page.

This module only validates the requests, fills the templates and shapes the answers. The LLM call (provider, cost
caps LLM_MAX_TOKENS / LLM_MAX_PROMPT_CHARS, token usage journal) and the prompt of a voice are the bridge's own,
injected by the composition root (radio_bridge.main) through two ports: `complete(messages)` and
`reply(sheet, history, text)`. A failure of either is an AiError with a stable code for the page. Standard library only.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Protocol

import persona_store

TEMPLATES_FILE = Path(__file__).resolve().parent / 'atelier_ai_templates.json'
SHEET_MAX_CHARS = 24000          # unsaved sheet text given to the LLM by a suggestion, cut beyond
MAX_DETAILS, DETAIL_MAX_CHARS = 16, 600   # details of a suggestion: flat {key: short text}
FREQUENCY_MARK = '%1'            # where the frequency goes in a sheet text (bridge/atelier/values.js FREQUENCY_MARK)
LLM_FREQUENCY = '{frequency}'    # what the LLM writes there
LANGUAGES = {'en': 'English', 'fr': 'French'}   # languages the workshop page and the suggestions know
NO_SHEET = '(no sheet yet: the voice is being created)'
MAX_HISTORY = 40                 # turns of a test conversation sent back by the page (radio_bridge.MAX_HISTORY)
ROLES = ('user', 'assistant')
_FENCE_RE = re.compile(r'^```[A-Za-z]*\s*\n?(.*?)\n?```$', re.S)
_SENTENCE_END_RE = re.compile(r'[.!?](?=\s|$)')
_DETAIL_KEY_RE = re.compile(r'[a-z_]{1,32}')
_SHEET_LANGUAGE_RE = re.compile(r'^language=([a-z]{2})\s*$', re.M)
_BAD_MARKS_RE = re.compile(r'[<>^]|%(?!1)')    # never in a call or a note line (persona_store, RS_Persona.lua)
_QUOTES = '"“”«»\'` '


class AiError(Exception):
    """Refused or failed workshop AI request: HTTP status, stable code and English message for the page."""

    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


class Complete(Protocol):
    def __call__(self, messages: list[dict[str, str]]) -> str: ...


class VoiceReply(Protocol):
    def __call__(self, sheet: persona_store.Persona, history: list[dict[str, str]], text: str) -> list[str]: ...


@dataclass(frozen=True)
class FieldSpec:
    """One text field the page can ask a suggestion for (an entry of the "suggest" section of the templates file)."""
    meaning: str
    max: int
    unit: str            # chars | bytes (UTF-8)
    language: str        # voice: the sheet's language= | page: the author's page
    frequency: bool      # the text must hold the frequency mark
    sentences: str       # one | line | paragraph: how the answer is shaped
    task: str
    sheet_required: bool = True


@dataclass(frozen=True)
class SuggestBook:
    common: str                     # lines opening every suggestion system text (its first line is the fake marker)
    fields: dict[str, FieldSpec]


UNITS, FIELD_LANGUAGES, SHAPES = ('chars', 'bytes'), ('voice', 'page'), ('one', 'line', 'paragraph')


def _read(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding='utf-8'))


def load_templates(path: Path = TEMPLATES_FILE) -> dict[str, dict[str, str]]:
    """{kind: {"system": text, "user": text}} of the prompt templates of the file (lists of lines joined)."""
    return {kind: {part: '\n'.join(lines) for part, lines in parts.items()}
            for kind, parts in _read(path).items() if not kind.startswith('_') and 'system' in parts}


def field_spec(name: str, entry: dict) -> FieldSpec:
    spec = FieldSpec(meaning=entry['meaning'], max=entry['max'], unit=entry['unit'], language=entry['language'],
                     frequency=bool(entry['frequency']), sentences=entry['sentences'], task='\n'.join(entry['task']),
                     sheet_required=bool(entry.get('sheet_required', True)))
    if not (isinstance(spec.max, int) and spec.max > 0 and spec.unit in UNITS and spec.language in FIELD_LANGUAGES
            and spec.sentences in SHAPES and spec.task.strip() and spec.meaning.strip()):
        raise ValueError(f"bad suggest entry '{name}' in {TEMPLATES_FILE.name}")
    return spec


def load_suggest(path: Path = TEMPLATES_FILE) -> SuggestBook:
    """The "suggest" section of the templates file: common lines and one FieldSpec per field."""
    section = _read(path)['suggest']
    return SuggestBook('\n'.join(section['common']),
                       {name: field_spec(name, entry) for name, entry in section['fields'].items()})


# --- request values --------------------------------------------------------------------------------------------------
def _bad(message: str) -> AiError:
    return AiError(400, 'bad_request', message)


def voice_id(value) -> str:
    if not isinstance(value, str) or not persona_store.ID_RE.fullmatch(value):
        raise _bad(f"invalid voice id {value!r}")
    return value


def text_value(value, name: str, required: bool = False) -> str:
    if value is None:
        value = ''
    if not isinstance(value, str):
        raise _bad(f"{name} must be a text")
    if required and not value.strip():
        raise _bad(f"{name} is empty")
    return value.strip()


def history_turns(value) -> list[dict[str, str]]:
    """Turns of the test conversation sent by the page: [{role: user | assistant, content}], the last MAX_HISTORY."""
    if value is None:
        return []
    if not isinstance(value, list):
        raise _bad("history must be a list")
    turns = []
    for turn in value:
        if not isinstance(turn, dict) or turn.get('role') not in ROLES or not isinstance(turn.get('content'), str):
            raise _bad("a history turn is {role: user | assistant, content: text}")
        turns.append({'role': turn['role'], 'content': turn['content']})
    return turns[-MAX_HISTORY:]


def language_value(value) -> str:
    """Language code of the page: en (default) or fr."""
    if value is None:
        return 'en'
    if value not in LANGUAGES:
        raise _bad(f"pageLanguage must be one of {', '.join(LANGUAGES)}")
    return value


def details_value(value) -> dict[str, str]:
    """Flat details of a suggestion: <= MAX_DETAILS keys [a-z_]{1,32}, short text values."""
    if value is None:
        return {}
    if not isinstance(value, dict) or len(value) > MAX_DETAILS:
        raise _bad(f"details must be an object of at most {MAX_DETAILS} keys")
    for key, text in value.items():
        if not _DETAIL_KEY_RE.fullmatch(key) or not isinstance(text, str) or len(text) > DETAIL_MAX_CHARS:
            raise _bad(f"a detail is a key [a-z_] and a text of at most {DETAIL_MAX_CHARS} characters")
    return {key: text.strip() for key, text in value.items()}


def sheet_language(sheet_text: str) -> str:
    """language= of a (maybe half written) sheet, read without parsing it; en by default."""
    match = _SHEET_LANGUAGE_RE.search(sheet_text)
    return match.group(1) if match else 'en'


# --- answers ---------------------------------------------------------------------------------------------------------
def plain_text(reply: str) -> str:
    """Answer of the LLM without a markdown fence around it."""
    text = (reply or '').strip()
    fenced = _FENCE_RE.match(text)
    return (fenced.group(1) if fenced else text).strip()


def _size(text: str, unit: str) -> int:
    return len(text.encode('utf-8')) if unit == 'bytes' else len(text)


def _head(text: str, limit: int, unit: str) -> str:
    """Longest start of `text` within `limit` (never half a character)."""
    if unit != 'bytes':
        return text[:limit]
    return text.encode('utf-8')[:limit].decode('utf-8', 'ignore')


def cut_words(text: str, limit: int, unit: str = 'chars') -> str:
    """`text` cut at a word end within `limit` (a single too long word is cut where it must)."""
    if _size(text, unit) <= limit:
        return text
    head = _head(text, limit, unit)
    if text[len(head)].isspace():
        return head.rstrip(',;: ')
    return head.rsplit(' ', 1)[0].rstrip(',;: ') if ' ' in head else head


def cut_sentence(text: str, limit: int, unit: str = 'chars') -> str:
    """`text` cut at a sentence end (else a word end) within `limit`."""
    if _size(text, unit) <= limit:
        return text
    head = _head(text, limit, unit)
    ends = [m.end() for m in _SENTENCE_END_RE.finditer(head)]
    return head[:ends[-1]].strip() if ends else cut_words(text, limit, unit)


def _lines(reply: str) -> list[str]:
    return [' '.join(line.split()) for line in plain_text(reply).splitlines() if line.strip()]


def one_sentence(reply: str, limit: int, unit: str = 'chars') -> str:
    """First line of the answer, unquoted, on one line, cut at a sentence end (else a word) within `limit`."""
    lines = _lines(reply)
    return cut_sentence((lines[0] if lines else '').strip(_QUOTES), limit, unit)


def one_line(reply: str, limit: int, unit: str = 'chars') -> str:
    """First line of the answer, unquoted, cut at a word end within `limit`."""
    lines = _lines(reply)
    return cut_words((lines[0] if lines else '').strip(_QUOTES), limit, unit)


def paragraph(reply: str, limit: int, unit: str = 'chars') -> str:
    """Every line of the answer joined in one paragraph, unquoted, cut at a sentence end within `limit`."""
    return cut_sentence(' '.join(_lines(reply)).strip(_QUOTES), limit, unit)


SHAPERS: dict[str, Callable[[str, int, str], str]] = {'one': one_sentence, 'line': one_line, 'paragraph': paragraph}


def frequency_text(text: str) -> str:
    """The LLM's frequency mark turned into the sheet's, without the characters a call or a note line refuses."""
    return _BAD_MARKS_RE.sub('', text.replace(LLM_FREQUENCY, '\0')).replace('\0', FREQUENCY_MARK)


# --- suggestion prompt -----------------------------------------------------------------------------------------------
def suggest_rules(spec: FieldSpec, language: str) -> list[str]:
    """Rules the bridge adds to a field's task, from its entry: language, shape, length, frequency mark."""
    if spec.unit == 'bytes':
        length = (f"Length: at most {spec.max} bytes: about {int(spec.max / 1.2)} letters, accented letters "
                  "count double.")
    else:
        length = f"Length: at most {spec.max} characters."
    shape = {'one': "Write one sentence (two short ones at most).", 'line': "Write one short line.",
             'paragraph': "Write one paragraph of a few sentences, without line breaks."}[spec.sentences]
    rules = [f"Write in {LANGUAGES.get(language, LANGUAGES['en'])}.", shape, length]
    if spec.frequency:
        rules.append("Write the literal " + LLM_FREQUENCY + " exactly once where the radio frequency goes: the game "
                     "puts the frequency there. Never write a frequency number yourself.")
    return rules


def suggest_user(field: str, spec: FieldSpec, page_language: str, details: dict[str, str], current: str,
                 sheet_text: str) -> str:
    """User message of a suggestion; author values are concatenated as data, never formatted."""
    lines = ["Field to fill: " + field + " \u2014 " + spec.meaning,
             "Page language of the author: " + LANGUAGES[page_language],
             "Details of what this field is for:"]
    lines += ["- " + key + ": " + value for key, value in details.items()] or ["- (none)"]
    if current:
        lines.append('Text in the field now: "' + current + '"')
    lines += ["The voice sheet being written (unsaved, may be incomplete):", "<<<",
              sheet_text[:SHEET_MAX_CHARS] if sheet_text else NO_SHEET, ">>>"]
    return '\n'.join(lines)


def shape_suggestion(spec: FieldSpec, reply: str) -> str:
    """The LLM's answer shaped for its field: plain text, shape and limit, frequency mark checked and turned into %1."""
    text = plain_text(reply)
    if spec.frequency:
        text = frequency_text(text)
    text = SHAPERS[spec.sentences](text, spec.max, spec.unit)
    if spec.frequency:
        text = frequency_text(text).strip()     # a cut may leave a lone %
    if not text:
        raise AiError(502, 'ai_failed', "the AI gave an empty answer")
    if spec.frequency and FREQUENCY_MARK not in text:
        raise AiError(502, 'ai_no_frequency', "the AI forgot the frequency mark")
    return text


# --- requests --------------------------------------------------------------------------------------------------------
class WorkshopAI:
    """The AI requests of the workshop over the injected LLM ports of the bridge."""

    def __init__(self, complete: Complete, reply: VoiceReply, log: Callable[[str], None],
                 templates: dict[str, dict[str, str]] | None = None, suggestions: SuggestBook | None = None):
        self._complete, self._reply, self._log = complete, reply, log
        self._templates = templates if templates is not None else load_templates()
        self._suggestions = suggestions if suggestions is not None else load_suggest()

    def _ask(self, kind: str, voice: str, values: dict[str, str]) -> str:
        template = self._templates[kind]
        self._log(f"workshop AI {kind} for voice '{voice}'")
        messages = [{'role': 'system', 'content': template['system']},
                    {'role': 'user', 'content': template['user'].format_map(values)}]
        return self._complete(messages)

    def personality(self, data: dict) -> str:
        voice = voice_id(data.get('voiceId'))
        values = {'name': text_value(data.get('name'), 'name') or voice,
                  'description': text_value(data.get('description'), 'description', required=True)}
        prompt = plain_text(self._ask('personality', voice, values))
        if not prompt:
            raise AiError(502, 'ai_failed', "the AI gave an empty answer")
        return prompt

    def suggest(self, data: dict) -> str:
        field = data.get('field')
        spec = self._suggestions.fields.get(field) if isinstance(field, str) else None
        if spec is None:
            raise _bad(f"no suggestion for the field {field!r}")
        voice = voice_id(data['voiceId']) if data.get('voiceId') is not None else None
        sheet_text = text_value(data.get('sheetText'), 'sheetText', required=spec.sheet_required)
        page_language = language_value(data.get('pageLanguage'))
        details = details_value(data.get('details'))
        current = text_value(data.get('current'), 'current')
        language = sheet_language(sheet_text) if spec.language == 'voice' else page_language
        system = '\n'.join([self._suggestions.common, spec.task, *suggest_rules(spec, language)])
        user = suggest_user(field, spec, page_language, details, current, sheet_text)
        self._log(f"workshop AI suggest {field} for voice '{voice or 'new'}'")
        reply = self._complete([{'role': 'system', 'content': system}, {'role': 'user', 'content': user}])
        return shape_suggestion(spec, reply)

    def try_voice(self, data: dict) -> list[str]:
        voice = voice_id(data.get('voiceId'))
        text = text_value(data.get('text'), 'text', required=True)
        history = history_turns(data.get('history'))
        sheet_text = data.get('sheetText')
        if not isinstance(sheet_text, str) or not sheet_text.strip():
            raise _bad("sheetText is empty")
        try:
            sheet = persona_store.parse_bytes(sheet_text.encode('utf-8'), voice)
        except persona_store.PersonaError as err:
            raise AiError(422, 'sheet_refused', f"the sheet is not valid yet: {err}") from None
        self._log(f"workshop AI try for voice '{voice}'")
        return self._reply(sheet, history, text)
