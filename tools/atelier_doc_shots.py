"""Screenshots of the voice workshop for the wiki and the README (E22-T09), French and English UI.

    python RadioSurvivor/tools/atelier_doc_shots.py [--out docs/images/screenshots/atelier]

Dev only (Playwright and a local stub of the AI provider, never a paid model). Same set-up as tools/atelier_smoke.py:
bridge/atelier_server.py on a random free port (never the user's 8765) over a temporary working folder copied from the
shipped sheets; the mod's folder and the user's folders are only read. An example voice, Rosie (a girl hiding in the
Muldraugh water tower: two places, two missions, rewards, a handwritten note and a spontaneous call), is written into
that temporary folder first, with a fake survey file of the game, a fake game console and a few bridge log lines.
Then, per locale (fr-FR, en-US) at 1280x800, it opens the page and writes atelier-<lang>-NN-<subject>.png:
01-voice (list and step 1), 02-where, 03-knows (help popover), 04-missions, 04b-places ("recorded in game"),
05-rewards, 06-trade (a shipped trader), 07-note, 08-try (test conversation), 09-journal, 10-refused (game banner).
The stub answers "Try the voice" with one fixed line in the language of the page (the fake LLM of tools/fake_llm
answers in English only outside the game).
Every sheet written is checked by the real game reader (RS_Persona.lua in lupa) before the pictures are taken.
"""
from __future__ import annotations

import argparse
import http.server
import json
import shutil
import sys
import tempfile
import threading
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]
ATELIER = ROOT / 'bridge' / 'atelier'
SHIPPED = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas'
OUT = ROOT / 'docs/images/screenshots/atelier'
sys.path.insert(0, str(ROOT / 'bridge'))
sys.path.insert(0, str(ROOT / 'tests'))
import atelier_server  # noqa: E402
import game_console  # noqa: E402
import log_buffer  # noqa: E402
import place_surveys  # noqa: E402
import radio_bridge  # noqa: E402
from test_atelier_ui import game_reads  # noqa: E402

VIEW = {'width': 1280, 'height': 800}
LOCALES = (('fr-FR', 'fr'), ('en-US', 'en'))

# Texts the player reads in the game follow the UI language; the facts, the stories and the personality stay in
# English, as the workshop asks (the AI plays the voice from them).
LOCAL = {
    'fr': {'description': "Une ado cachée dans le château d'eau de Muldraugh",
           'tower': "Château d'eau de Muldraugh", 'dumpster': "Benne au pied du château d'eau",
           'call': "Il y a quelqu'un ? Ici Rosie sur %1. Je vois toute la ville d'ici. À vous.",
           'note': ("Rosie, château d'eau", 'Appelle-moi sur %1', 'Le matin et le soir'),
           'say': "Rosie, tu m'entends ? Je suis à l'école.", 'try': "Allô, il y a quelqu'un ?",
           'reply': "Je t'entends. Reste loin de la grande rue, elle est pleine de morts. À vous.",
           'answer': "Je t'entends. T'es où ? Moi, je vois toute la ville d'ici. À vous.",
           'say2': "J'ai une morsure au bras, qu'est-ce que je fais ?",
           'reply2': "Nettoie-la tout de suite et serre un bandage propre. Je suis désolée, mon chou. À vous.",
           'by': 'Kate Smith'},
    'en': {'description': 'A teenager hiding in the Muldraugh water tower',
           'tower': 'Muldraugh water tower', 'dumpster': 'Dumpster under the water tower',
           'call': 'Is anyone out there? This is Rosie on %1. I can see the whole town from up here. Over.',
           'note': ('Rosie, water tower', 'Call me on %1', 'Mornings and evenings'),
           'say': 'Rosie, can you hear me? I am at the school.', 'try': 'Hello, is anyone there?',
           'reply': 'I hear you. Stay off the main street, it is full of the dead. Over.',
           'answer': 'I hear you. Where are you? I can see the whole town from up here. Over.',
           'say2': 'I got bitten on the arm, what do I do?',
           'reply2': 'Clean it right now and tie a clean bandage. I am sorry, honey. Over.',
           'by': 'Kate Smith'},
}

ROSIE = """# {description}
format=1
id=rosie
name=Rosie Calloway
language={lang}
frequency_range=50.0-54.8
radio=any
listen=06:00-09:00,19:00-23:00
location=none
knows=From the top of the water tower she sees every street of Muldraugh, from the school to the highway.
knows=Which houses on her street still have food: she watched the families leave.
ignores=What the army is doing.
secret=She is fifteen and alone up there since her dad went out for water and did not come back.
actions=say,mark_map,start_mission,share_frequency
shares=darlene
call_one_in=5
call={call}
state=active

[place tower]
at=10676,9790,0
label={tower}
use=mark,target

[place dumpster]
at=10681,9796,0
label={dumpster}
use=drop

[mission food]
type=deliver
items=food
quantity=2-3
drops=dumpster
story=I ran out of canned food two days ago. Leave some in the dumpster, I will climb down at night.

[mission clear_tower]
type=clear
target=tower
after=food
story=The dead keep walking around the tower. Thin them out so I can get down safely.

[rewards]
pool=stashmap:4, frequency:2, lesson:Aiming:1

[note]
text={note0}
text={note1}
text={note2}
loot=BedroomDresser:2
loot=SchoolLockers:1
corpse=yes

[prompt]
You are Rosie Calloway, 15, a high school girl from Muldraugh, Kentucky. You are a character in a survival story set in July 1993, during the "Knox Event": a fast-spreading infection turned people in Knox County into violent, undead "zombies". The army sealed the area behind a fence: the Knox Exclusion Zone.

Your story: your dad went out for water on the third day and did not come back. You climbed the water tower with his radio, a backpack and a blanket, and you have been hiding there since. You watch the town with his binoculars and you know which streets are full of the dead. You are brave, a bit sarcastic, and you hide how scared you are at night.

You are talking over a two-way radio with people still trapped inside the Exclusion Zone. You cannot see them and you do not know where they are.

Rules:
- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.
- Never invite anyone to come up the tower and never tell anyone you are alone, unless they earned your trust.
- No game mechanics and no exact coordinates.
- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown. End each transmission with "Over." (or the equivalent in the caller's language, e.g. "À vous." in French).
- Answer in the same language the caller uses.
"""

# A voice with a typing mistake, refused by the game (hours written 8:00 instead of 08:00).
TOMMY = """# {description}
format=1
id=tommy
name=Tommy Reyes
language={lang}
frequency_range=56.0-58.8
listen=8:00-12:00
actions=say

[prompt]
You are Tommy Reyes, 16, hiding in the basement of the Muldraugh school. Radio style: short sentences, end with "Over."
"""
TOMMY_DESCRIPTION = {'fr': "Mon deuxième essai : un garçon dans la cave de l'école",
                     'en': 'My second try: a boy in the school basement'}
TOMMY_REASON = "bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)"

SURVEYS = ('# RadioSurvivor places recorded for the voice workshop\n'
           'time=2026-11-15 18:02:00\tgame=1993-07-09 07:12\tby={by}\tat=10668,9801,0\troom=kitchen\t'
           'building=10664,9797,10673,9806\n'
           'time=2026-11-15 18:06:00\tgame=1993-07-09 07:20\tby={by}\tat=10681,9796,0\t'
           'containers=bin:trash_01_0\n')


class StubProvider(http.server.ThreadingHTTPServer):
    """An OpenAI-compatible chat endpoint on a free local port: every answer is `reply`, as a structured radio reply."""
    reply = ''

    def __init__(self):
        super().__init__(('127.0.0.1', 0), StubHandler)


class StubHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 (http.server API)
        self.rfile.read(int(self.headers.get('Content-Length') or 0))
        content = json.dumps({'say': self.server.reply, 'actions': []}, ensure_ascii=False)
        body = json.dumps({'id': 'stub', 'object': 'chat.completion', 'model': 'stub',
                           'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': content},
                                        'finish_reason': 'stop'}],
                           'usage': {'prompt_tokens': 1, 'completion_tokens': 1, 'total_tokens': 2}}).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def strings(lang: str) -> dict:
    return json.loads((ATELIER / 'i18n' / f'{lang}.json').read_text(encoding='utf-8'))


def write_sheets(working: Path, lang: str) -> None:
    """Rosie and Tommy in the temporary working folder; Rosie must be accepted by the game reader."""
    local = LOCAL[lang]
    rosie = ROSIE.format(lang=lang, description=local['description'], call=local['call'], tower=local['tower'],
                         dumpster=local['dumpster'], note0=local['note'][0], note1=local['note'][1],
                         note2=local['note'][2])
    verdict = game_reads(rosie, 'rosie')
    if verdict[0] != 'OK':
        raise SystemExit(f'{lang}: the game reader refuses Rosie: {verdict[1]}')
    (working / 'rosie.txt').write_text(rosie, encoding='utf-8', newline='\n')
    tommy = TOMMY.format(lang=lang, description=TOMMY_DESCRIPTION[lang])
    (working / 'tommy.txt').write_text(tommy, encoding='utf-8', newline='\n')


def console_lines(tommy_line: int) -> str:
    prefix = 'LOG  : General      f:0> [batman_RadioSurvivor]     [RadioSurvivor] personas: '
    return (f"{prefix}voice 'rosie' loaded: state active, frequencies 52.4\n"
            f'{prefix}ERROR: batman_RadioSurvivor/personas/tommy.txt refused, line {tommy_line}: {TOMMY_REASON}\n')


def shoot(page, out: Path, name: str, clip: dict | None = None) -> None:
    path = out / name
    page.screenshot(path=str(path), clip=clip, animations='disabled', caret='hide')
    print(f'{name}: {path.stat().st_size // 1024} KB')


def pill(page, n: int) -> None:
    page.locator('.pill').nth(n).click()
    page.mouse.move(0, 0)
    page.evaluate('window.scrollTo(0, 0)')


def scroll_to(page, locator) -> None:
    locator.evaluate("e => e.scrollIntoView({block: 'start'})")
    page.evaluate('window.scrollBy(0, -12)')


def run_locale(browser, locale: str, lang: str, out: Path, provider: StubProvider) -> None:
    t = strings(lang)
    local = LOCAL[lang]
    provider.reply = local['answer']
    radio_bridge.LOG_BUFFER = log_buffer.LogBuffer()     # a journal per locale (radio_bridge.log writes to it)
    with tempfile.TemporaryDirectory() as tmp:
        working = Path(tmp) / 'personas'
        shutil.copytree(SHIPPED, working, ignore=shutil.ignore_patterns('_*'))
        write_sheets(working, lang)
        tommy_line = next(i for i, line in enumerate((working / 'tommy.txt').read_text(encoding='utf-8')
                                                     .splitlines(), 1) if line.startswith('listen='))
        console = Path(tmp) / 'console.txt'
        console.write_text(console_lines(tommy_line), encoding='utf-8', newline='')
        survey_file = Path(tmp) / place_surveys.FILE_NAME
        survey_file.write_text(SURVEYS.format(by=local['by']), encoding='utf-8', newline='\n')
        running = threading.Event()
        running.set()
        live = atelier_server.Live(radio_bridge.LOG_BUFFER, game_console.GameConsole(console, radio_bridge.LOG_BUFFER),
                                   running.is_set, surveys=place_surveys.SurveyFile(survey_file))
        radio_bridge.TOKEN_USAGE = radio_bridge.TokenUsageLog(Path(tmp) / 'token_usage.jsonl')
        live.ai = radio_bridge.workshop_ai({'OPENAI_BASE_URL': f'http://127.0.0.1:{provider.server_port}/v1',
                                            'OPENAI_MODEL': 'stub', 'OPENAI_KEY': 'stub'})
        store = atelier_server.VoiceStore(working, SHIPPED)
        server = atelier_server.bind(store, 0, ATELIER, atelier_server.mod_version(SHIPPED), lambda *a: None,
                                     live=live)
        atelier_server.start(server)
        try:
            radio_bridge.log(f"{local['by']} -> rosie : {local['say']}")
            radio_bridge.log(f"reply of voice 'rosie': {local['reply']}")
            radio_bridge.log(f"Jim Baker -> darlene : {local['say2']}")
            radio_bridge.log(f"reply of voice 'darlene': {local['reply2']}")
            context = browser.new_context(locale=locale, viewport=VIEW, device_scale_factor=1)
            page = context.new_page()
            errors: list[str] = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(server.url)
            expect(page.locator('h1')).to_have_text(t['app.title'])
            page.locator('.voice', has_text='Rosie Calloway').first.click()
            expect(page.locator('.pill.on')).to_contain_text(t['step.who'])
            page.mouse.move(0, 0)
            shoot(page, out, f'atelier-{lang}-01-voice.png')

            pill(page, 1)                                                        # where and when, down to the call
            page.get_by_label(t['where.call'], exact=True).evaluate("e => e.scrollIntoView({block: 'end'})")
            page.evaluate('window.scrollBy(0, 40)')
            shoot(page, out, f'atelier-{lang}-02-where.png')

            pill(page, 2)                                                        # what she knows, with a help popover
            button = page.locator('button.hint[data-topic="help.head.actions.start_mission"]').first
            button.scroll_into_view_if_needed()
            page.evaluate('window.scrollBy(0, 160)')
            button.click()
            expect(page.locator('#help-pop')).to_be_visible()
            shoot(page, out, f'atelier-{lang}-03-knows.png')
            page.keyboard.press('Escape')

            pill(page, 3)                                                        # missions
            page.locator('details.fold').first.evaluate('d => d.open = false')
            scroll_to(page, page.locator('details.fold').first)
            shoot(page, out, f'atelier-{lang}-04-missions.png')
            page.locator('details.fold').first.evaluate('d => d.open = true')     # places recorded in game
            expect(page.locator('li.survey')).to_have_count(2)
            block = page.locator('.surveys-block')
            scroll_to(page, block)
            box = block.bounding_box()
            shoot(page, out, f'atelier-{lang}-04b-places.png',
                  clip={'x': box['x'] - 16, 'y': max(0, box['y'] - 4), 'width': box['width'] + 32,
                        'height': box['height'] + 16})

            pill(page, 4)                                                        # rewards
            expect(page.locator('.card.reward').first).to_be_visible()
            shoot(page, out, f'atelier-{lang}-05-rewards.png')

            note = page.locator('details.fold', has_text=t['advanced.note.enable'])
            note.locator(':scope > summary').click()
            scroll_to(page, note)
            shoot(page, out, f'atelier-{lang}-07-note.png')

            page.locator('.voice', has_text='Boone Tackett').first.click()       # a shipped trader
            pill(page, 4)
            trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
            trade.locator(':scope > summary').click()
            expect(trade.locator('.stock-line').first.locator('.item-kg')).not_to_have_text('')
            scroll_to(page, trade)
            shoot(page, out, f'atelier-{lang}-06-trade.png')

            page.locator('.voice', has_text='Tommy Reyes').first.click()         # refused by the game
            expect(page.locator('.verdict')).to_be_visible(timeout=15000)
            page.mouse.move(0, 0)
            page.evaluate('window.scrollTo(0, 0)')
            shoot(page, out, f'atelier-{lang}-10-refused.png')

            page.locator('#tab-journal').click()                                 # live journal
            expect(page.locator('.journal-list .jrow').filter(has_text='rosie')).not_to_have_count(0, timeout=10000)
            page.mouse.move(0, 0)
            shoot(page, out, f'atelier-{lang}-09-journal.png')
            page.locator('#tab-voices').click()                                  # try the voice
            page.locator('.voice', has_text='Rosie Calloway').first.click()
            pill(page, 1)
            page.locator('#try-open').click()                                   # try the voice
            page.locator('#try-input').fill(local['try'])
            page.locator('#try-send').click()
            expect(page.locator('.try-drawer .msg.assistant')).to_have_count(1, timeout=15000)
            page.mouse.move(0, 0)
            shoot(page, out, f'atelier-{lang}-08-try.png')
            page.locator('.try-drawer').get_by_role('button', name=t['ai.try_close']).click()

            if errors:
                raise SystemExit(f'{lang}: page errors: {errors}')
            context.close()
        finally:
            server.shutdown()
            server.server_close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--out', type=Path, default=OUT)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    provider = StubProvider()
    threading.Thread(target=provider.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            for locale, lang in LOCALES:
                run_locale(browser, locale, lang, args.out, provider)
            browser.close()
    finally:
        provider.shutdown()
        provider.server_close()
    print('summary: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
