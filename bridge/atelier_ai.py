"""Workshop AI requests (E22-T06, ADR atelier-voix D04): the bridge's LLM helps to write a voice sheet.

Three requests of the voice workshop page (bridge/atelier_server.py routes /api/ai/*):

    personality   an English [prompt] text in the structure of the delivered sheets, from a few sentences of the
                  author in any language (instructions: atelier_ai_templates.json, data, English);
    story         the one sentence (<= STORY_MAX_CHARS, the reader's limit) a voice says to give a mission;
    try_voice     one turn of a test conversation with the voice, its sheet read from the UNSAVED text of the page.

This module only validates the requests, fills the templates and shapes the answers. The LLM call (provider, cost
caps LLM_MAX_TOKENS / LLM_MAX_PROMPT_CHARS, token usage journal) and the prompt of a voice are the bridge's own,
injected by the composition root (radio_bridge.main) through two ports: `complete(messages)` and
`reply(sheet, history, text)`. A failure of either is an AiError with a stable code for the page. Standard library only.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Callable, Protocol

import persona_store

TEMPLATES_FILE = Path(__file__).resolve().parent / 'atelier_ai_templates.json'
STORY_MAX_CHARS = 200            # story= of a [mission] section (the reader cuts beyond, the page input too)
MAX_LIST_ITEMS = 50              # knows / ignores / secret lines given to the personality request
MAX_HISTORY = 40                 # turns of a test conversation sent back by the page (radio_bridge.MAX_HISTORY)
ROLES = ('user', 'assistant')
_FENCE_RE = re.compile(r'^```[A-Za-z]*\s*\n?(.*?)\n?```$', re.S)
_SENTENCE_END_RE = re.compile(r'[.!?](?=\s|$)')


class AiError(Exception):
    """Refused or failed workshop AI request: HTTP status, stable code and English message for the page."""

    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


class Complete(Protocol):
    def __call__(self, messages: list[dict[str, str]]) -> str: ...


class VoiceReply(Protocol):
    def __call__(self, sheet: persona_store.Persona, history: list[dict[str, str]], text: str) -> list[str]: ...


def load_templates(path: Path = TEMPLATES_FILE) -> dict[str, dict[str, str]]:
    """{kind: {"system": text, "user": text}} of the templates file (lists of lines joined)."""
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    return {kind: {part: '\n'.join(lines) for part, lines in parts.items()}
            for kind, parts in data.items() if not kind.startswith('_')}


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


def text_list(value, name: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or len(value) > MAX_LIST_ITEMS or not all(isinstance(v, str) for v in value):
        raise _bad(f"{name} must be a list of at most {MAX_LIST_ITEMS} texts")
    return [v.strip() for v in value if v.strip()]


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


def listed(values: list[str]) -> str:
    return '; '.join(values) if values else '(nothing given)'


# --- answers ---------------------------------------------------------------------------------------------------------
def plain_text(reply: str) -> str:
    """Answer of the LLM without a markdown fence around it."""
    text = (reply or '').strip()
    fenced = _FENCE_RE.match(text)
    return (fenced.group(1) if fenced else text).strip()


def one_sentence(reply: str, limit: int = STORY_MAX_CHARS) -> str:
    """First line of the answer, unquoted, on one line, cut at a sentence end (else a word) within `limit`."""
    lines = [line for line in plain_text(reply).splitlines() if line.strip()]
    text = ' '.join((lines[0] if lines else '').split()).strip('"“”\'` ')
    if len(text) <= limit:
        return text
    head = text[:limit]
    ends = [m.end() for m in _SENTENCE_END_RE.finditer(head)]
    if ends:
        return head[:ends[-1]].strip()
    return head.rsplit(' ', 1)[0].rstrip(',;: ') if ' ' in head else head


# --- requests --------------------------------------------------------------------------------------------------------
class WorkshopAI:
    """The three AI requests of the workshop over the injected LLM ports of the bridge."""

    def __init__(self, complete: Complete, reply: VoiceReply, log: Callable[[str], None],
                 templates: dict[str, dict[str, str]] | None = None):
        self._complete, self._reply, self._log = complete, reply, log
        self._templates = templates if templates is not None else load_templates()

    def _ask(self, kind: str, voice: str, values: dict[str, str]) -> str:
        template = self._templates[kind]
        self._log(f"workshop AI {kind} for voice '{voice}'")
        messages = [{'role': 'system', 'content': template['system']},
                    {'role': 'user', 'content': template['user'].format_map(values)}]
        return self._complete(messages)

    def personality(self, data: dict) -> str:
        voice = voice_id(data.get('voiceId'))
        values = {'name': text_value(data.get('name'), 'name') or voice,
                  'description': text_value(data.get('description'), 'description', required=True),
                  'knows': listed(text_list(data.get('knows'), 'knows')),
                  'ignores': listed(text_list(data.get('ignores'), 'ignores')),
                  'secret': listed(text_list(data.get('secret'), 'secret'))}
        prompt = plain_text(self._ask('personality', voice, values))
        if not prompt:
            raise AiError(502, 'ai_failed', "the AI gave an empty answer")
        return prompt

    def story(self, data: dict) -> str:
        voice = voice_id(data.get('voiceId'))
        values = {'mission_type': text_value(data.get('missionType'), 'missionType', required=True),
                  'voice_text': text_value(data.get('voiceText'), 'voiceText') or '(no description)',
                  'context': text_value(data.get('context'), 'context') or '(no description)'}
        story = one_sentence(self._ask('story', voice, values))
        if not story:
            raise AiError(502, 'ai_failed', "the AI gave an empty answer")
        return story

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
