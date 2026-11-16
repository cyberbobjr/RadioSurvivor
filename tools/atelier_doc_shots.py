"""Screenshots of the voice workshop for the wiki and the README (E22-T09), French and English UI.

    python RadioSurvivor/tools/atelier_doc_shots.py [--out docs/images/screenshots/atelier]

Dev only (Playwright and a local stub of the AI provider, never a paid model). Same set-up as tools/atelier_smoke.py:
bridge/atelier_server.py on a random free port (never the user's 8765) over a temporary working folder copied from the
shipped sheets; the mod's folder is only read and the user's own folders (Zomboid/Lua) are never read. Each shot gets only
what it needs: the voices of the mod stay as delivered, except Walt, changed for the 13-restore shot only. An example voice, Rosie (a girl hiding in the
Muldraugh water tower: two places, two missions, rewards, a handwritten note and a spontaneous call), is written into
that temporary folder first, with a fake survey file of the game, a fake game console and a few bridge log lines.
Then, per locale (fr-FR, en-US) at 1280x800, it opens the page and writes atelier-<lang>-NN-<subject>.png:
01-voice (list and step 1), 02-where, 03-personality (help popover), 04-missions, 04b-places ("recorded in game"),
05-rewards, 06-trade (a shipped trader), 07-note, 08-try (test conversation), 09-journal, 10-refused (game banner),
11-login (login page of the network mode, E22-T15), and for the reference page 13 (E22-T16): 12-new (new voice
form), 13-restore (a changed voice of the mod, "back to the mod's version" asked), 14-import (import of an id that
exists), 15-browser (item browser), 16-ai-personality ("Write it with the AI" with its answer), 17-saved (saved, the
game reads it again).
The four example voices of the wiki page 14 are loaded from that page itself (```persona blocks, read by
tests/test_wiki_voice_examples.py) and photographed under exemples/: 21-opal-where, 22-tibbs-missions,
23-tibbs-rewards, 24-sol-trade, 25-wendell-trade.
The stub answers "Try the voice" with one fixed line in the language of the page (the fake LLM of tools/fake_llm
answers in English only outside the game), and "Write it with the AI" with a fixed English personality.
Every sheet written is checked by the real game reader (RS_Persona.lua in lupa) before the pictures are taken.
"""
from __future__ import annotations

import argparse
import contextlib
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
EXAMPLES_DIR = 'exemples'                 # pictures of the example voices of the wiki page 14
sys.path.insert(0, str(ROOT / 'bridge'))
sys.path.insert(0, str(ROOT / 'tests'))
import atelier_auth  # noqa: E402
import atelier_server  # noqa: E402
import game_console  # noqa: E402
import log_buffer  # noqa: E402
import place_surveys  # noqa: E402
import radio_bridge  # noqa: E402
from test_atelier_ui import game_reads  # noqa: E402
from test_wiki_voice_examples import GameReader, example_sheets  # noqa: E402

VIEW = {'width': 1280, 'height': 800}
LOCALES = (('fr-FR', 'fr'), ('en-US', 'en'))

# Texts the player reads in the game follow the UI language; the facts, the stories and the personality stay in
# English, as the workshop asks (the AI plays the voice from them).
LOCAL = {
    'fr': {'description': "Une ado cachée dans le château d'eau de Muldraugh",
           'tower': "Château d'eau de Muldraugh", 'dumpster': "Cabane près du château d'eau",
           'call': "Il y a quelqu'un ? Ici Rosie sur %1. Je vois toute la ville d'ici. À vous.",
           'note': ("Rosie, château d'eau", 'Appelle-moi sur %1', 'Le matin et le soir'),
           'say': "Rosie, tu m'entends ? Je suis à l'école.", 'try': "Allô, il y a quelqu'un ?",
           'reply': "Je t'entends. Reste loin de la grande rue, elle est pleine de morts. À vous.",
           'answer': "Je t'entends. T'es où ? Moi, je vois toute la ville d'ici. À vous.",
           'say2': "J'ai une morsure au bras, qu'est-ce que je fais ?",
           'reply2': "Nettoie-la tout de suite et serre un bandage propre. Je suis désolée, mon chou. À vous.",
           'by': 'Kate Smith', 'new_name': 'Mae Tolliver',
           'describe': "Une infirmière épuisée qui a quitté sa clinique de West Point la nuit où tout a commencé. "
                       "Elle veut y retourner. Elle parle doucement et s'inquiète pour tout le monde."},
    'en': {'description': 'A teenager hiding in the Muldraugh water tower',
           'tower': 'Muldraugh water tower', 'dumpster': 'Shed by the water tower',
           'call': 'Is anyone out there? This is Rosie on %1. I can see the whole town from up here. Over.',
           'note': ('Rosie, water tower', 'Call me on %1', 'Mornings and evenings'),
           'say': 'Rosie, can you hear me? I am at the school.', 'try': 'Hello, is anyone there?',
           'reply': 'I hear you. Stay off the main street, it is full of the dead. Over.',
           'answer': 'I hear you. Where are you? I can see the whole town from up here. Over.',
           'say2': 'I got bitten on the arm, what do I do?',
           'reply2': 'Clean it right now and tie a clean bandage. I am sorry, honey. Over.',
           'by': 'Kate Smith', 'new_name': 'Mae Tolliver',
           'describe': 'A tired nurse who left her West Point clinic the night it all began. She wants to go back. '
                       'She talks softly and worries about everyone.'},
}

# Answer of the stub to "Write it with the AI" (English, as the workshop asks for a personality).
PERSONALITY = ('You are Mae Tolliver, 46, a nurse from West Point, Kentucky. You are a character in a survival story '
               'set in July 1993, during the "Knox Event".\n\nYour story: you left your clinic the night it all began, '
               'and you want to go back. You talk softly and you worry about everyone.\n\nRules:\n'
               '- Stay in character at all times.\n- Radio style: 1 to 4 short sentences. End with "Over."\n'
               '- Answer in the same language the caller uses.')
# A comment line put on top of a shipped sheet: the voice shows as "changed" (13-restore).
CHANGED_MARK = '# Changed in the workshop\n'

ROSIE = """# {description}
format=1
id=rosie
name=Rosie Calloway
language={lang}
frequency_range=50.0-54.8
radio=any
listen=06:00-09:00,19:00-23:00
location=none
actions=say,mark_map,start_mission,share_frequency
shares=darlene
call_one_in=5
call={call}
state=active

[place tower]
at=10604,10622,0
label={tower}
use=mark,target

[place dumpster]
at=10617,10617,0
label={dumpster}
use=drop

[mission food]
type=deliver
items=food
quantity=2-3
drops=dumpster
story=I ran out of canned food two days ago. Leave some in the locker of the shed, I will climb down at night.

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

Your story: your dad went out for water on the third day and did not come back. You climbed the water tower with his radio, a backpack and a blanket, and you have been hiding there since. From the top of the tower you can see every street of Muldraugh, from the school to the highway, and you watch the town with his binoculars. You have no idea what the army is doing. You are brave, a bit sarcastic, and you hide how scared you are at night.

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
           'time=2026-11-15 18:02:00\tgame=1993-07-09 07:12\tby={by}\tat=10617,10554,0\troom=dinerkitchen\t'
           'building=10610,10553,10627,10563\n'
           'time=2026-11-15 18:06:00\tgame=1993-07-09 07:20\tby={by}\tat=10617,10617,0\troom=shed\t'
           'building=10615,10617,10617,10620\tcontainers=metal_shelves:furniture_storage_02_0\n')


class StubProvider(http.server.ThreadingHTTPServer):
    """An OpenAI-compatible chat endpoint on a free local port: every answer is `reply`, as a structured radio reply,
    or `text` as is while it is set (the personality written by the AI)."""
    reply = ''
    text = None

    def __init__(self):
        super().__init__(('127.0.0.1', 0), StubHandler)


class StubHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 (http.server API)
        self.rfile.read(int(self.headers.get('Content-Length') or 0))
        content = self.server.text if self.server.text is not None else json.dumps(
            {'say': self.server.reply, 'actions': []}, ensure_ascii=False)
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
    reader = GameReader()
    for voice_id, text in example_sheets(lang):                     # the voices of the wiki page 14, as written there
        verdict = reader.read(text, voice_id)
        if verdict[0] != 'OK':
            raise SystemExit(f'{lang}: the game reader refuses the example {voice_id}: {verdict[1]}')
        (working / f'{voice_id}.txt').write_text(text, encoding='utf-8', newline='\n')


def console_lines(tommy_line: int) -> str:
    prefix = 'LOG  : General      f:0> [batman_RadioSurvivor]     [RadioSurvivor] personas: '
    return (f"{prefix}voice 'rosie' loaded: state active, frequencies 52.4\n"
            f'{prefix}ERROR: batman_RadioSurvivor/personas/tommy.txt refused, line {tommy_line}: {TOMMY_REASON}\n')


def shoot(page, out: Path, name: str, clip: dict | None = None) -> None:
    path = out / name
    page.screenshot(path=str(path), clip=clip, animations='disabled', caret='hide')
    print(f'{name}: {path.stat().st_size // 1024} KB')


def shoot_region(page, out: Path, name: str, *locators, pad: int = 12, fixed: bool = False) -> None:
    """Picture of the region covering every locator, with a margin: in page coordinates (the region may be taller than
    the window), or in the window for a fixed element such as a modal dialog (`fixed`)."""
    locators[0].scroll_into_view_if_needed()
    page.mouse.move(0, 0)
    sx, sy = (0, 0) if fixed else page.evaluate('[window.scrollX, window.scrollY]')
    boxes = [loc.bounding_box() for loc in locators]
    left = min(b['x'] for b in boxes) + sx - pad
    top = min(b['y'] for b in boxes) + sy - pad
    right = max(b['x'] + b['width'] for b in boxes) + sx + pad
    bottom = max(b['y'] + b['height'] for b in boxes) + sy + pad
    clip = {'x': max(0, left), 'y': max(0, top), 'width': right - max(0, left), 'height': bottom - max(0, top)}
    path = out / name
    page.screenshot(path=str(path), clip=clip, full_page=not fixed, animations='disabled', caret='hide')
    print(f'{name}: {path.stat().st_size // 1024} KB')


def open_voice(page, name: str) -> None:
    page.locator('#tab-voices').click()
    page.locator('.voice', has_text=name).first.click()
    expect(page.locator('#main .toolbar h2')).to_have_text(name)        # drawn once the voice is read
    page.mouse.move(0, 0)


def fold_open(page, title: str):
    """The panel (details.fold) whose title is `title`, opened; returns it."""
    panel = page.locator('details.fold', has=page.locator(':scope > summary', has_text=title)).first
    if not panel.evaluate('d => d.open'):
        panel.locator(':scope > summary').click()
    return panel


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

            pill(page, 2)                                                        # personality, with a help popover
            button = page.locator('button.hint[data-topic="help.head.actions.start_mission"]').first
            button.scroll_into_view_if_needed()
            page.evaluate('window.scrollBy(0, 160)')
            button.click()
            expect(page.locator('#help-pop')).to_be_visible()
            shoot(page, out, f'atelier-{lang}-03-personality.png')
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

            shoot_reference(page, out, lang, provider, working)
            shoot_examples(page, out / EXAMPLES_DIR, lang)
            if errors:
                raise SystemExit(f'{lang}: page errors: {errors}')
            context.close()
        finally:
            server.shutdown()
            server.server_close()


@contextlib.contextmanager
def changed_walt(page, working: Path):
    """Walt, a voice of the mod, changed in the working folder for the 13-restore shot only, then put back as
    delivered: every other shot shows the voices of the mod unchanged. The page reads the list again each time."""
    walt = working / 'walt.txt'
    walt.write_text(CHANGED_MARK + (SHIPPED / 'walt.txt').read_text(encoding='utf-8'), encoding='utf-8', newline='\n')
    page.reload()
    try:
        yield
    finally:
        shutil.copyfile(SHIPPED / 'walt.txt', walt)
        page.reload()


def shoot_reference(page, out: Path, lang: str, provider: StubProvider, working: Path) -> None:
    """12 to 17: the screens of the reference page 13 not shown by the walk through Rosie's steps."""
    t = strings(lang)
    local = LOCAL[lang]
    rosie = (working / 'rosie.txt').read_bytes()
    page.locator('#tab-voices').click()                                  # 12-new: the new voice form, filled
    page.locator('#new-voice').click()
    page.locator('#new-name').fill(local['new_name'])
    expect(page.locator('#new-id')).to_have_value(local['new_name'].split(' ')[0].lower())
    shoot_region(page, out, f'atelier-{lang}-12-new.png', page.locator('article.welcome'))

    with changed_walt(page, working):                                    # 13-restore: a changed voice of the mod
        open_voice(page, 'Walt Hensley')
        expect(page.locator('#main .toolbar .badge.modified')).to_be_visible()
        page.locator('#main .toolbar').get_by_role('button', name=t['editor.action_restore']).click()
        notice = page.locator('.notice[role=alertdialog]')
        expect(notice).to_contain_text('Walt Hensley')                 # the voice's name, not its id
        page.evaluate('window.scrollTo(0, 0)')
        shoot_region(page, out, f'atelier-{lang}-13-restore.png', page.locator('#main .toolbar'), notice)
        notice.get_by_role('button', name=t['dialog.cancel']).click()

    open_voice(page, 'Rosie Calloway')                                   # 14-import: this id exists already
    page.locator('input[type=file]').set_input_files(
        files=[{'name': 'rosie.txt', 'mimeType': 'text/plain', 'buffer': rosie}])
    ask = page.locator('.notice[role=dialog]')
    expect(ask).to_be_visible()
    page.evaluate('window.scrollTo(0, 0)')
    shoot_region(page, out, f'atelier-{lang}-14-import.png', page.locator('#main .toolbar'), ask)
    ask.get_by_role('button', name=t['dialog.cancel']).click()

    open_voice(page, 'Boone Tackett')                                    # 15-browser: the item browser
    pill(page, 4)
    trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
    trade.locator(':scope > summary').click()
    trade.get_by_role('button', name=t['browser.open']).first.click()
    browser = page.locator('dialog.item-browser')
    browser.locator('.browser-search').fill('whisky')
    expect(browser.locator('[role=option]').first).to_be_visible()
    shoot_region(page, out, f'atelier-{lang}-15-browser.png', browser.locator(':scope > article'), pad=0, fixed=True)
    page.keyboard.press('Escape')
    expect(browser).to_have_count(0)

    open_voice(page, 'Rosie Calloway')                                   # 16-ai-personality: written by the AI
    pill(page, 2)
    page.locator('#ai-personality-open').click()
    panel = page.locator('#ai-personality')
    panel.locator('textarea.ai-description').fill(local['describe'])
    provider.text = PERSONALITY
    try:
        page.locator('#ai-personality-generate').click()
        expect(panel.locator('.ai-result')).to_be_visible(timeout=15000)
    finally:
        provider.text = None
    shoot_region(page, out, f'atelier-{lang}-16-ai-personality.png', page.locator('#ai-personality-open'), panel,
                 pad=6)

    page.locator('#save').click()                                        # 17-saved: the game reads it again
    expect(page.locator('.toast.show')).to_contain_text(t['code.voice_saved'])
    page.evaluate('window.scrollTo(0, 0)')
    page.mouse.move(0, 0)
    shoot(page, out, f'atelier-{lang}-17-saved.png')


def shoot_examples(page, out: Path, lang: str) -> None:
    """21 to 25: the key steps of the four example voices of the wiki page 14."""
    t = strings(lang)
    out.mkdir(parents=True, exist_ok=True)
    page.locator('.toast.show').click()                                  # the "saved" message of 17 goes away
    expect(page.locator('.toast.show')).to_have_count(0)
    open_voice(page, 'Opal Brannigan')                                   # listening hours and spontaneous call
    pill(page, 1)
    shoot_region(page, out, f'atelier-{lang}-21-opal-where.png', page.locator('.step-body'))

    open_voice(page, 'Vernon Tibbs')                                     # two chained missions
    pill(page, 3)
    page.locator('details.fold').first.evaluate('d => d.open = false')
    cards = page.locator('article.card.mission')
    expect(cards).to_have_count(2)
    shoot_region(page, out, f'atelier-{lang}-22-tibbs-missions.png', cards.first, cards.last)

    pill(page, 4)                                                        # rewards and own category
    own = fold_open(page, t['advanced.category'])
    page.evaluate('window.scrollTo(0, 0)')
    shoot_region(page, out, f'atelier-{lang}-23-tibbs-rewards.png', page.locator('.card.reward').first, own)

    for name, picture in (('Marisol Vega', '24-sol-trade'), ('Wendell Ames', '25-wendell-trade')):  # trade panels
        open_voice(page, name)
        pill(page, 4)
        trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
        trade.locator(':scope > summary').click()
        expect(trade.locator('.stock-line').first.locator('.item-kg')).not_to_have_text('')
        shoot_region(page, out, f'atelier-{lang}-{picture}.png', trade)


def shoot_login(browser, locale: str, lang: str, out: Path) -> None:
    """11-login: the login page of the network mode (E22-T15), password typed, behind a gate built here (bridge/.env
    is not read)."""
    t = strings(lang)
    with tempfile.TemporaryDirectory() as tmp:
        store = atelier_server.VoiceStore(Path(tmp) / 'personas', SHIPPED)
        gate = atelier_server.NetworkGate(atelier_auth.Authenticator('example password', lambda *a: None))
        server = atelier_server.bind(store, 0, ATELIER, None, lambda *a: None, gate=gate)
        atelier_server.start(server)
        try:
            context = browser.new_context(locale=locale, viewport=VIEW, device_scale_factor=1)
            page = context.new_page()
            page.goto(server.url)
            expect(page.locator('h2')).to_have_text(t['login.heading'])
            page.get_by_label(t['login.password'], exact=True).fill('example password')
            box = page.locator('.login-card').bounding_box()
            shoot(page, out, f'atelier-{lang}-11-login.png',
                  clip={'x': box['x'] - 24, 'y': box['y'] - 24, 'width': box['width'] + 48, 'height': box['height'] + 48})
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
                shoot_login(browser, locale, lang, args.out)
            browser.close()
    finally:
        provider.shutdown()
        provider.server_close()
    print('summary: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
