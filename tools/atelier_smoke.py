"""Browser smoke test of the voice workshop (E22-T03): the real page in Chromium, French then English.

    python RadioSurvivor/tools/atelier_smoke.py [--shots <folder>]

Starts bridge/atelier_server.py on a free port over a temporary working folder (a copy of the shipped sheets; the
mod's folder is only read), opens the page with the locale fr-FR then en-US, checks the dashboard shown first (E24-T05:
a row per voice, the trade filter, an empty filter cleared, a row opening its voice), creates a voice through the assistant with
nothing technical typed (E24-T02): its name only (the id made from the first name, a tooltip at most), the voice type
"mission giver" (its action ticked, "Talk" locked), hours from the cards then custom, the spontaneous call as a named
step with the frequency put in by its button, the personality language French (the starter text follows), a map mark
made with "New place…" without leaving the voice (E25-T03: a shared place, its square typed, user decision), a
deliver mission whose quantity is two steppers and whose dead drop is made the same way (points only), a barricade
mission after it aimed at the mark's place, with a story state written as a sentence, a scout mission "further away"
in a church, a reward hidden at the dead drop; saves it, checks what the simple controls wrote and that the real game
reader (RS_Persona.lua in lupa) accepts it. Where and when (E24-T01): the first radio card is ticked for a new voice;
another card is picked; the switch "choose the frequency myself" shows one field, filled with a free frequency of that
radio, whose badge names the radio a typed frequency needs (and no radio at all off the grid); switched off, the radio
of that frequency is ticked; the saved sheet has radio= and no frequency=. Exports it (same text) and imports it back
as a new voice (one button, the next free id). Then reopens it, looks at the page at 800 px wide (no horizontal scroll)
and takes a screenshot per language.
Live part (E22-T04, E22-T10), in French: a fake game console refuses the voice at its radio line and the bridge logs
a line through radio_bridge.log: red mark in the list, banner with the reason in words (the game's own words folded,
no line number), button "fix it" to the "where" step, the Journal
tab shows both lines and filters them (screenshots atelier-verdict-fr.png, atelier-journal-fr.png). In English, the
bridge loop is said stopped: the Journal tab explains that only the game lines appear.
AI part (E22-T06), against the deterministic fake LLM (tools/fake_llm, never a paid model): in French, "Write it with
the AI" writes the personality and "Use it" replaces the prompt after the in-page confirm, "Suggest" (E24-T04) fills
the voice's name and a mission story, "Try the voice" answers from the unsaved sheet and Reset empties it, the working
file untouched (screenshot atelier-ai-fr.png); in the note panel, "Suggest" fills a line whose frequency shows as the
word on screen and %1 in the sheet. In English the AI is said unavailable: the buttons, "Suggest" included, are greyed
with the configuration tooltip.
Map position pasted (user 2026-11-16), in both languages, in the Places tab: "7966, 11751, 1" pasted into the x field of
a place fills x, y and the floor, the map link and the saved places file; the square typed before is pasted back.
Places tab (E25-T03), in both languages: master/detail (user 2026-11-17): the list of the places on the left, the
form of the place picked only on the right; no left list on the Dashboard and the Journal, the voice list in the Voices
tab only. A place the voice uses says so and its deletion is refused naming the voice; an area made from two corners
and a floor is picked once made, saved, then deleted once confirmed; at 390 px the list sits above the form, no
horizontal scroll (screenshots atelier-places-<lang>.png, atelier-places-390-<lang>.png).
Chances, trade and note (E22-T12), in French: a reward set to "Often" is written with weight 4; the trade panel makes
its meeting point with "New place…" (a shared spot, ticked), picks the arrival card and
the visits as a named step, adds stock items from the item list (no item name typed: search, category, ticks, "Ajouter
la sélection"), shows each as its name, no weight, its Module.Type as tooltip only, replaces a line from the same list
and removes one, ticks a category and adds an item to what the voice accepts (E23-T06), makes a paquet from a typed
name (its id made and hidden) with an item from the list, picks the margin card "Rapace" then an exact value; the note
panel counts its text, puts the frequency in by its button, says the note is already hidden everywhere papers are
found and adds a themed place under "Aussi dans..." (E24-T03); the voice is saved and accepted by the game reader (screenshots atelier-rewards-fr.png,
atelier-items-fr.png, atelier-trade-fr.png, atelier-note-fr.png).
Stock grid and item browser (user 2026-11-15), in French, on a shipped voice (Boone): two stock lines
have their cells at the same x and width at 1280 and 800 px; "Ajouter ce qu'elle vend" opens the
item list, filtered by a category: an item already in the stock is shown as such, a click and Enter tick two items that
stay ticked across searches, Escape adds nothing, "Ajouter la sélection" adds them (screenshots atelier-stock-aligned-fr.png, atelier-item-browser-fr.png).
Sellable stock, older copies and confirmations (E22-T17): the trader's stock offers only the items a trader can sell
(an axe is not found, the browser says so); a copy of Walt the game wrote from an older version of the mod shows
"Ancienne version" / "Older version" with its tooltip; the removal asked names the voice, not its id.
Places recorded in game (E22-T08, E25-T03), in French: a fake survey file of the game (a kitchen, then a dumpster) is
listed newest first in the Places tab; "Ajouter aux lieux" asks the name prefilled from the dumpster, makes a shared
place at its square, the record then says it is already a place; the places file is accepted by the bridge reader, the
survey file untouched (screenshot atelier-surveys-fr.png).
Network mode (E22-T15), in both languages, on a second server behind the password gate: the page goes to the login
page, a wrong password is said wrong, the right one opens the workshop, its logout button goes back to the login page,
five failures lock with the seconds to wait; no password in the journal (screenshot atelier-login-<lang>.png).
Fails on any browser console error. Dev only (Playwright + lupa), not part of tests/run_all.py.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
import threading
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]
ATELIER = ROOT / 'bridge' / 'atelier'
SHIPPED = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas'
sys.path.insert(0, str(ROOT / 'bridge'))
for _folder in ('commun', 'coreai', 'radiosurvivor'):   # offline test folders (E26: tests/<folder>/)
    sys.path.insert(0, str(ROOT / 'tests' / _folder))
import atelier_auth  # noqa: E402
import atelier_server  # noqa: E402
import game_console  # noqa: E402
import persona_store  # noqa: E402
import place_surveys  # noqa: E402
import radio_bridge  # noqa: E402
from test_atelier_ui import game_reads  # noqa: E402
_bridge_log = radio_bridge.log
from test_fake_llm import start_fake, stop  # noqa: E402
import fake_llm  # noqa: E402  (tools/fake_llm, put on the path by test_fake_llm)
radio_bridge.log = _bridge_log   # test_fake_llm quiets the bridge log on import: the live journal needs it

LOCALES = (('fr-FR', 'fr'), ('en-US', 'en'))


def strings(lang: str) -> dict:
    return json.loads((ATELIER / 'i18n' / f'{lang}.json').read_text(encoding='utf-8'))


def working_places(working: Path) -> str:
    """Shared places the game reads (E25-T03): the working _places.txt the workshop writes, else the delivered one."""
    path = working / persona_store.PLACES_FILE
    return (path if path.is_file() else SHIPPED / persona_store.PLACES_FILE).read_text(encoding='utf-8')


def make_place(page, scope, t: dict, label: str, at: tuple[str, str, str], points: bool) -> None:
    """E25-T03: "New place…" of a list in `scope`: the form opens in the page, a spot named and its square typed (the
    map link follows), made; only a spot is offered where a point is needed."""
    scope.locator('button.place-new').first.click()
    dialog = page.locator('.notice.new-place')
    expect(dialog).to_be_visible()
    if points != (dialog.locator('.place-kind').count() == 0):
        raise AssertionError(f'"New place…" offers an area where a spot is needed ({label})')
    dialog.get_by_label(t['places.label'], exact=True).fill(label)
    map_link = dialog.locator('a.maplink')
    expect(map_link).to_have_attribute('href', 'https://zomboidmap.com/')
    expect(map_link).to_have_text(t['map.home'])
    for axis, value in zip(('x', 'y', t['places.floor']), at):
        dialog.get_by_label(axis, exact=True).fill(value)
    expect(map_link).to_have_attribute('href', f'https://zomboidmap.com/#11/{at[0]}/{at[1]}/f{at[2]}')
    expect(map_link).to_have_attribute('target', '_blank')
    dialog.locator('button.place-create').click()
    expect(page.locator('.toast')).to_contain_text(t['places.created'].replace('{name}', label))


def check_radio_choice(page, t: dict) -> None:
    """E24-T01: the radio cards, then the switch "choose the frequency myself" and its badge; ends on the radio
    tactical."""
    cards = page.locator('label.radio-card')
    expect(cards).to_have_count(5)
    expect(cards.first.locator('input')).to_be_checked()                   # new voice: everybody hears it
    expect(cards.first).to_contain_text(t['radio.any_talkie.who'])
    page.locator('label.radio-card[data-level="military"]').click()
    expect(page.locator('label.radio-card[data-level="military"] input')).to_be_checked()
    page.get_by_role('switch', name=t['where.fixed_toggle']).check()
    expect(cards).to_have_count(0)
    field = page.get_by_label(t['where.fixed'], exact=True)
    expect(field).to_have_value('0.2')                                     # first free frequency of the military zone
    badge = page.locator('.radio-badge')
    expect(badge).to_contain_text(t['radio.military.name'])
    field.fill('145')
    expect(badge).to_contain_text(t['radio.any_talkie.name'])
    field.fill('1000.2')
    expect(badge).to_contain_text(t['where.badge_none'].split('{')[0].strip())
    field.fill('320.0')
    expect(badge).to_contain_text(t['radio.tactical.name'])
    page.get_by_role('switch', name=t['where.fixed_toggle']).uncheck()
    expect(page.locator('label.radio-card[data-level="tactical"] input')).to_be_checked()
    expect(page.get_by_label(t['where.fixed'], exact=True)).to_have_count(0)


def check_dashboard(page, t: dict, lang: str, shots: Path, failures: list[str]) -> None:
    """E24-T05: the dashboard is the view shown first; a row per voice of the folder (16 shipped at least); the trade
    chip leaves only traders; a filter that matches nothing says so with a button that clears it; the table scrolls in
    its own box at 800 px; a click on a row opens that voice in the editor (screenshot atelier-dashboard-<lang>.png)."""
    try:
        expect(page.locator('#tab-dashboard')).to_have_attribute('aria-selected', 'true')
        expect(page.locator('#dashboard')).to_be_visible()
        expect(page.locator('#main')).to_be_hidden()
        expect(page.locator('aside.side:visible')).to_have_count(0)         # user 2026-11-17: no list, full width
        rows = page.locator('#dashboard tr.dash-row')
        expect(rows.first).to_be_visible()
        expect(page.locator('#dashboard .dash-tile')).to_have_count(6)
        total = rows.count()
        if total < 16:
            failures.append(f'{lang}: dashboard shows {total} voices, 16 shipped at least')
        walt = rows.filter(has_text='Walt Hensley')
        expect(walt).to_have_count(1)
        expect(walt).to_contain_text(t['dashboard.hours.always'])
        expect(walt.locator('.dash-radio')).to_contain_text(t['dashboard.radio.any_talkie'])
        page.locator('.dash-chip[data-filter=kind][data-value=trade]').click()
        expect(rows.filter(has_text='Walt Hensley')).to_have_count(0)
        traders = rows.count()
        with_tag = rows.filter(has=page.locator('.dash-tag[data-kind=trade]')).count()
        if not traders or traders != with_tag:
            failures.append(f'{lang}: trade filter left {traders} rows, {with_tag} of them traders')
        expect(rows.filter(has_text='Gus Lacombe')).to_contain_text(t['dashboard.tag.trade.boat'])
        page.locator('.dash-chip[data-filter=level][data-value=military]').click()
        expect(page.locator('#dashboard .dash-empty')).to_contain_text(t['dashboard.empty'])
        page.locator('#dash-clear').click()
        expect(rows).to_have_count(total)
        page.locator('.dash-sort[data-sort=name]').click()
        names = rows.locator('.dash-open b').all_inner_texts()
        if names != sorted(names, key=str.casefold):
            failures.append(f'{lang}: sort by name gave {names}')
        page.mouse.move(0, 0)
        page.screenshot(path=str(shots / f'atelier-dashboard-{lang}.png'), full_page=True)
        page.set_viewport_size({'width': 800, 'height': 900})
        width = page.evaluate('document.documentElement.scrollWidth')
        if width > 800:
            failures.append(f'{lang}: dashboard scrolls sideways at 800 px ({width} px)')
        page.set_viewport_size({'width': 1280, 'height': 900})
        rows.filter(has_text='Darlene Pruitt').locator('.dash-htext').click()
        expect(page.locator('#tab-voices')).to_have_attribute('aria-selected', 'true')
        expect(page.locator('#main .toolbar h2')).to_have_text('Darlene Pruitt')
        voices = page.locator('#voices aside.side .voice')                  # the voice list: in the Voices tab
        expect(voices.filter(has_text='Darlene Pruitt')).to_have_attribute('aria-current', 'true')
        expect(page.locator('#places .place-item:visible')).to_have_count(0)
        print(f'{lang}: dashboard first, no left list, {total} voices, {traders} traders with the trade filter, empty filter cleared, '
              f'page width at 800 px = {width}, a row opened Darlene')
    except AssertionError as err:
        failures.append(f'{lang}: dashboard: {err}')


def show_text(page, t: dict, on: bool) -> None:
    """Shows or hides the text the game reads (the "..." menu of the toolbar, E24-T02)."""
    wanted = t['editor.preview'] if on else t['editor.preview_hide']
    menu = page.locator('details.more-menu')
    if not menu.evaluate('d => d.open'):
        menu.locator(':scope > summary').click()
    button = menu.get_by_role('button', name=wanted, exact=True)
    if button.count():
        button.click()
    else:
        menu.locator(':scope > summary').click()                           # already in the wanted state: closed


def create_voice(page, t: dict, voice_id: str, name: str) -> None:
    """E24-T02: nothing technical typed. The name only (the id is made from the first name), the voice type "mission
    giver" (its action ticked), hours from the cards then custom, a spontaneous call as a named step with the
    frequency put in by its button, shared places made from the lists without leaving the voice (their square typed,
    user decision), a mission whose quantity is two steppers, one whose story state is a sentence, an objective
    "further away" in a church, a hidden reward's place."""
    page.locator('#new-voice').click()
    page.locator('#new-name').fill(name)
    page.locator('label.choice-card[data-value="missions"]').click()
    page.locator('#new-create').click()
    expect(page.locator('.pill.on')).to_contain_text(t['step.who'])
    expect(page.locator('#main .toolbar h2')).to_have_attribute('title', voice_id)   # the id: a tooltip at most
    page.get_by_label(t['who.description'], exact=True).fill('A voice made by the smoke test')
    next_button = page.locator('#step-next')

    next_button.click()                                                    # 2: where and when
    expect(page.locator('.pill.on')).to_contain_text(t['step.where'])
    check_radio_choice(page, t)
    page.locator('label.choice-card[data-value="night"]').click()
    page.locator('label.choice-card[data-value="custom"]').click()
    page.get_by_role('button', name=t['where.add_hours']).click()
    page.locator('[data-scale="scale.head.call_one_in"] button[data-step="often"]').click()
    call = page.get_by_label(t['where.call'], exact=True)
    call.fill(t['where.call'] + ' ')
    page.get_by_role('button', name=t['freq.add']).click()
    expect(call).to_have_value(re.compile(re.escape(t['freq.word'])))

    next_button.click()                                                    # 3: personality
    expect(page.locator('.pill.on')).to_contain_text(t['step.personality'])
    expect(page.locator('.check', has_text=t['action.start_mission']).locator('input')).to_be_checked()
    expect(page.locator('.check', has_text=t['action.say']).locator('input')).to_be_disabled()
    page.locator('label.choice-card[data-value="fr"]').click()             # the personality written in French
    expect(page.locator('textarea.prompt')).to_have_value(re.compile('^Tu es '))

    next_button.click()                                                    # 4: map marks and missions
    lang = voice_id.removeprefix('smoke')                                  # place names of this run, unique
    marks = page.locator('section.question.marks')
    make_place(page, marks, t, f'Old mill {lang}', ('10600', '9300', '0'), points=False)
    expect(marks.locator('.check', has_text=f'Old mill {lang}').locator('input')).to_be_checked()
    page.locator('.type-card', has_text=t['mission.deliver']).click()
    deliver = page.locator('.card.mission').last
    deliver.get_by_label(t['param.items'], exact=True).select_option('medical')
    deliver.get_by_label(t['field.min'], exact=True).fill('2')
    deliver.get_by_label(t['field.max'], exact=True).fill('3')
    deliver.get_by_role('button', name=f"{t['field.max']} +", exact=True).click()   # the stepper: 3 -> 4
    deliver.get_by_label(t['mission.story'], exact=True).fill('Leave some bandages by the dumpster.')
    make_place(page, deliver, t, f'Dumpster behind the mill {lang}', ('10610', '9305', '0'), points=True)
    deliver = page.locator('.card.mission').last
    expect(deliver.locator('.check', has_text=f'Dumpster behind the mill {lang}').locator('input')).to_be_checked()
    page.locator('.type-card', has_text=t['mission.barricade']).click()
    barricade = page.locator('.card.mission').last
    barricade.locator('select.place-select').select_option(f'old_mill_{lang}')
    barricade = page.locator('.card.mission').last
    if barricade.locator('select.building-select').count():
        raise AssertionError('a kind of building is offered for an exact spot')
    barricade.get_by_label(t['param.count'], exact=True).fill('4')
    barricade.get_by_label(t['mission.after'], exact=True).select_option(index=1)
    barricade.get_by_label(t['mission.sets_state'], exact=True).fill('Le moulin est barricadé')
    page.locator('.type-card', has_text=t['mission.scout']).click()
    scout = page.locator('.card.mission').last
    expect(scout.locator('select.place-select')).to_have_value('near')   # no target=: near the player
    scout.locator('select.place-select').select_option('far')
    scout = page.locator('.card.mission').last
    scout.locator('select.building-select').select_option('church')
    if page.locator('.step-body').get_by_text(f'old_mill_{lang}').count():
        raise AssertionError('a place shows its id')

    next_button.click()                                                    # 5: rewards
    page.locator('.type-card', has_text=t['reward.cache']).click()
    page.locator('.type-card', has_text=t['reward.lesson']).click()
    cache = page.locator('.row', has_text=t['rewards.cache_place'])
    cache.locator('select.place-select').select_option(f'dumpster_behind_the_mill_{lang}')
    page.locator('#save').click()
    expect(page.locator('.toast')).to_contain_text(t['code.voice_created'])


def check_simple_sheet(text: str, lang: str, failures: list[str]) -> None:
    """What the simple controls wrote: steppers, named steps, the frequency mark, the story state and its line, the
    language of the personality (E24-T02)."""
    wanted = ('\nquantity=2-4\n', '\ncall_one_in=3\n', '%1', '\nsets_state=le_moulin_est_barricade\n',
              'Story state: when your story state is le_moulin_est_barricade, Le moulin est barricadé',
              '\nlanguage=fr\n', '\nactions=say,start_mission\n', f'\nmarks=old_mill_{lang}\n',
              f'\ndrops=dumpster_behind_the_mill_{lang}\n', f'\ntarget=old_mill_{lang}\n',
              '\ntarget=far\nbuilding=church\n', f'\ncache_place=dumpster_behind_the_mill_{lang}\n')
    missing = [w for w in wanted if w not in text]
    print(f'{lang}: simple controls written: {"all" if not missing else missing}')
    if missing:
        failures.append(f'{lang}: the sheet misses {missing}\n{text}')


def check_live(page, t: dict, lang: str, voice_id: str, name: str, sheet: str, console: Path, running, shots: Path,
               failures: list[str]) -> None:
    """E22-T04 and E22-T10 in the page: the game's verdict and the live journal."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    if lang == 'fr':
        line = next(i for i, text in enumerate(sheet.splitlines(), 1) if text.startswith('radio='))
        reason = ('radio and frequency cannot be used together (a radio level to draw a free frequency, or one fixed '
                  'frequency)')
        with console.open('a', encoding='utf-8', newline='') as handle:
            handle.write(f'LOG  : General      f:0> [batman_RadioSurvivor]     [RadioSurvivor] personas: ERROR: '
                         f'batman_RadioSurvivor/personas/{voice_id}.txt refused, line {line}: {reason}\n')
        radio_bridge.log(f'Smoke -> {voice_id} : hello from the smoke test')
        voice = page.locator('.voice', has_text=name).first
        expect(voice.locator('.gamebad')).to_be_visible(timeout=15000)
        voice.click()
        banner = page.locator('.verdict')
        expect(banner).to_contain_text(t['verdict.title'].replace('{step}', t['step.where']))
        expect(banner).to_contain_text(t['verdict.why.radio'])
        expect(banner.locator('details.verdict-raw')).not_to_have_attribute('open', '')   # the game's words: folded
        expect(banner.locator('details.verdict-raw code')).to_have_text(reason)
        page.locator('#verdict-go').click()
        expect(page.locator('.pill.on')).to_contain_text(t['step.where'])
        print(f'{lang}: refusal at line {line}: red mark, banner (no line number, the words of the game folded) and '
              '"fix it" to the where step')
        page.screenshot(path=str(shots / f'atelier-verdict-{lang}.png'), full_page=True)
        page.locator('#tab-journal').click()
        expect(page.locator('aside.side:visible')).to_have_count(0)         # user 2026-11-17: no list, full width
        rows = page.locator('.journal-list .jrow')
        expect(rows.filter(has_text='hello from the smoke test')).to_have_count(1, timeout=10000)
        expect(rows.filter(has_text=f'{voice_id}.txt refused')).to_have_count(1)
        page.locator('#journal-voice').select_option(voice_id)
        page.locator('#journal-source').select_option('bridge')
        expect(rows.filter(has_text=f'{voice_id}.txt refused')).to_have_count(0)
        expect(rows.filter(has_text='hello from the smoke test')).to_have_count(1)
        page.locator('#journal-source').select_option('')
        page.locator('#journal-voice').select_option(voice_id)
        print(f'{lang}: journal shows the bridge line and the game line, filters by voice and source work')
        page.screenshot(path=str(shots / f'atelier-journal-{lang}.png'), full_page=True)
        page.locator('#tab-voices').click()
        return
    running.clear()
    page.locator('#tab-journal').click()
    if page.locator('aside.side:visible').count():
        failures.append(f'{lang}: a left list shows in the Journal tab')
    expect(page.locator('.journal-note').first).to_contain_text(t['journal.no_bridge'], timeout=10000)
    print(f'{lang}: bridge loop stopped: the journal says only game lines appear')
    running.set()
    page.locator('#tab-voices').click()


def paste_position(field, text: str) -> None:
    """A paste of `text` into `field`, as the browser sends it (a clipboard event carrying the text)."""
    field.evaluate("""(el, text) => {
      const data = new DataTransfer();
      data.setData('text/plain', text);
      el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
    }""", text)


def check_paste(page, t: dict, lang: str, working: Path, failures: list[str]) -> None:
    """User 2026-11-16, E25-T03: a position copied on the map ("7966, 11751, 1") pasted into the x field of a place of
    the Places tab fills x, y and the floor, the map link and the saved places file; the square of before is pasted
    back."""
    page.locator('#tab-places').click()
    page.locator(f'#places .place-item[data-id="old_mill_{lang}"]').click()
    card = page.locator(f'.card.place[data-place="old_mill_{lang}"]')
    status = page.locator('.places-status')
    x, y, floor = (card.get_by_label(axis, exact=True) for axis in ('x', 'y', t['places.floor']))
    before = [x.input_value(), y.input_value(), floor.input_value()]
    paste_position(x, '7966, 11751, 1')
    expect(x).to_have_value('7966')
    expect(y).to_have_value('11751')
    expect(floor).to_have_value('1')
    expect(card.locator('a.maplink')).to_have_attribute('href', 'https://zomboidmap.com/#11/7966/11751/f1')
    expect(card.get_by_text(t['map.paste_tip'], exact=True)).to_be_visible()
    if not card.locator('button.paste-square').count():
        failures.append(f'{lang}: no "{t["map.paste"]}" button on localhost')
    expect(status).to_have_text(t['places.saved'])
    if 'at=7966,11751,1' not in working_places(working):
        failures.append(f'{lang}: the pasted square is not in the places file')
    paste_position(y, ', '.join(before))
    expect(status).to_have_text(t['places.saved'])
    page.wait_for_timeout(700)
    if 'at=' + ','.join(before) not in working_places(working):
        failures.append(f'{lang}: the square pasted back is not in the places file')
    print(f'{lang}: map position "7966, 11751, 1" pasted into x in the Places tab: x, y and floor filled, map link '
          'and places file follow')
    page.locator('#tab-voices').click()


def check_places(page, t: dict, lang: str, name: str, working: Path, shots: Path, failures: list[str]) -> None:
    """E25-T03, user 2026-11-17: the Places tab is a master/detail: the list of the places on the left (no voice list),
    the form of the place picked on the right only. It names the voices using a place and refuses its deletion; a new
    area made from two corners and a floor is picked once made and saved, then deleted once confirmed (the next place is
    picked); at 390 px the list sits above the form, without horizontal scroll."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    page.locator('#tab-places').click()
    items = page.locator('#places .place-item')
    expect(items.first).to_be_visible()
    expect(page.locator('#voices aside.side')).to_be_hidden()               # the voice list: Voices tab only
    page.locator('#places-home').click()                                   # nothing picked: the tab's home
    expect(page.locator('#places .card.place')).to_have_count(0)
    item = page.locator(f'#places .place-item[data-id="old_mill_{lang}"]')
    item.click()
    expect(item).to_have_attribute('aria-current', 'true')
    expect(page.locator('#places .card.place')).to_have_count(1)           # the form of the place picked only
    mill = page.locator(f'.card.place[data-place="old_mill_{lang}"]')
    expect(mill.locator('.used-by')).to_contain_text(name)
    expect(item.locator('.md-sub')).not_to_have_text(t['places.used_none'])   # "used by N voices" under its name
    mill.get_by_role('button', name=t['places.remove']).click()
    refused = t['places.in_use'].split('{voices}')[0].replace('{name}', f'Old mill {lang}')
    expect(page.locator('.toast')).to_contain_text(refused)
    if f'[place old_mill_{lang}]' not in working_places(working):
        failures.append(f'{lang}: a used place was deleted')
    page.locator('#place-new').click()
    dialog = page.locator('.notice.new-place')
    label = 'Quartier du moulin' if lang == 'fr' else 'Mill town'
    dialog.get_by_label(t['places.label'], exact=True).fill(label)
    dialog.locator('label.choice-card[data-value="zone"]').click()
    corners = dialog.locator('.square')
    expect(corners).to_have_count(2)
    for index, (x, y) in enumerate((('10800', '9500'), ('10500', '9200'))):
        corners.nth(index).get_by_label('x', exact=True).fill(x)
        corners.nth(index).get_by_label('y', exact=True).fill(y)
    dialog.locator('input.place-floor').fill('0')
    dialog.locator('button.place-create').click()
    zone_id = 'quartier_du_moulin' if lang == 'fr' else 'mill_town'
    zone_item = page.locator(f'#places .place-item[data-id="{zone_id}"]')
    expect(zone_item).to_have_attribute('aria-current', 'true')            # the place made is picked
    zone = page.locator(f'.card.place[data-place="{zone_id}"]')
    expect(zone.locator('.used-by')).to_have_text(t['places.unused'])
    expect(page.locator('#places .card.place')).to_have_count(1)
    text = working_places(working)
    if f'[place {zone_id}]' not in text or 'area=10500,9200,10800,9500,0' not in text:
        failures.append(f'{lang}: the area is not in the places file\n{text}')
    try:
        persona_store.parse_places_lines(persona_store.split_lines(text))
    except persona_store.PersonaError as err:
        failures.append(f'{lang}: the bridge reader refuses the places file: {err}')
    page.screenshot(path=str(shots / f'atelier-places-{lang}.png'), full_page=True)
    page.set_viewport_size({'width': 390, 'height': 844})
    width = page.evaluate('document.documentElement.scrollWidth')
    if width > 390:
        failures.append(f'{lang}: horizontal scroll of the Places tab at 390 px ({width} px)')
    side, form = page.locator('#places aside.side').bounding_box(), zone.bounding_box()
    if not side or not form or side['y'] + side['height'] > form['y'] + 1:
        failures.append(f'{lang}: at 390 px the list of the places is not above the form ({side}, {form})')
    page.screenshot(path=str(shots / f'atelier-places-390-{lang}.png'), full_page=True)
    page.set_viewport_size({'width': 1280, 'height': 900})
    ids = items.evaluate_all('(els) => els.map((el) => el.dataset.id)')
    after = ids[ids.index(zone_id) + 1] if ids.index(zone_id) + 1 < len(ids) else ids[ids.index(zone_id) - 1]
    zone.get_by_role('button', name=t['places.remove']).click()
    page.locator('.notice.danger').get_by_role('button', name=t['places.remove']).click()
    expect(zone).to_have_count(0)
    expect(zone_item).to_have_count(0)
    expect(page.locator(f'#places .place-item[data-id="{after}"]')).to_have_attribute('aria-current', 'true')
    expect(page.locator('.places-status')).to_have_text(t['places.saved'])
    if f'[place {zone_id}]' in working_places(working):
        failures.append(f'{lang}: the deleted area is still in the places file')
    print(f'{lang}: Places tab as master/detail: list on the left, one form; "Old mill {lang}" used by {name}, '
          f'deletion refused; area {zone_id} made and picked, saved, deleted after confirm ({after} picked next); '
          f'width at 390 px = {width}, list above the form')
    page.locator('#tab-voices').click()


def check_propose(field, button, wanted: str) -> None:
    """Clicks a "Suggest" and waits for the fake LLM's proposal in its field, the button usable again."""
    button.click()
    expect(field).to_have_value(wanted, timeout=15000)
    expect(button).to_be_enabled(timeout=15000)


def check_ai(page, t: dict, lang: str, path: Path, shots: Path, failures: list[str]) -> None:
    """E22-T06 and E24-T04 in the page: the AI panel, "Suggest" on the voice name and a mission story, the test
    conversation (fr), greyed buttons (en)."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    before = path.read_bytes()
    if lang != 'fr':
        for pill in (0, 3):                                                # who, places and missions
            page.locator('.pill').nth(pill).click()
            proposes = page.locator('button.propose')
            if not proposes.count():
                failures.append(f'{lang}: no "Suggest" button on step {pill + 1}')
            for index in range(proposes.count()):
                expect(proposes.nth(index)).to_be_disabled()
                expect(proposes.nth(index)).to_have_attribute('title', t['ai.unavailable'])
    page.locator('.pill').nth(2).click()                                   # personality
    opener = page.locator('#ai-personality-open')
    if lang != 'fr':
        expect(opener).to_be_disabled()
        if opener.get_attribute('title') != t['ai.unavailable']:
            failures.append(f'{lang}: greyed AI button without the configuration tooltip')
        expect(page.locator('#try-open')).to_have_attribute('title', t['ai.unavailable'])
        print(f'{lang}: no AI configured: buttons ("Suggest" included) greyed with the configuration tooltip')
        return
    page.locator('.pill').nth(0).click()                                   # who: the voice's name proposed
    name_field = page.get_by_label(t['who.name'], exact=True)
    name = name_field.input_value()
    name_button = page.locator('button.propose[data-field="name"]')
    expect(name_button).to_have_text(t['ai.propose'])
    check_propose(name_field, name_button, fake_llm.WORKSHOP_SUGGEST_TEXTS['name'])
    print(f'{lang}: voice name proposed')
    name_field.fill(name)                                                  # the list still finds the voice by name
    page.locator('.pill').nth(2).click()
    opener.click()
    page.locator('#ai-personality .ai-description').fill("Un vieux mécanicien qui répare des radios dans son garage.")
    page.locator('#ai-personality-generate').click()
    expect(page.locator('#ai-personality .ai-result')).to_contain_text('Your story:', timeout=15000)
    page.locator('#ai-personality-use').click()
    page.locator('#ai-personality .notice').get_by_role('button', name=t['ai.use']).click()   # the prompt was not empty
    expect(page.locator('textarea.prompt')).to_have_value(re.compile('Your story:'))
    print(f'{lang}: personality written by the AI and used after the in-page confirm')
    page.locator('.pill').nth(3).click()                                   # missions
    card = page.locator('.card.mission').first
    check_propose(card.get_by_label(t['mission.story'], exact=True),
                  card.locator('button.propose[data-field="mission_story"]'),
                  fake_llm.WORKSHOP_SUGGEST_TEXTS['mission_story'])
    print(f'{lang}: mission story proposed')
    page.locator('#try-open').click()
    page.locator('#try-input').fill('Hello, is anyone there?')
    page.locator('#try-send').click()
    expect(page.locator('.try-drawer .msg.assistant')).to_have_count(1, timeout=15000)
    expect(page.locator('.try-drawer .msg.user')).to_have_count(1)
    page.screenshot(path=str(shots / f'atelier-ai-{lang}.png'), full_page=True)
    page.locator('#try-reset').click()
    expect(page.locator('.try-drawer .msg')).to_have_count(0)
    print(f'{lang}: test conversation answered from the unsaved sheet, reset')
    if path.read_bytes() != before:
        failures.append(f'{lang}: the AI changed the working file')


def check_help(page, t: dict, lang: str, shots: Path, failures: list[str]) -> None:
    """The "?" of a mission type card and of an action open a popover with the text, inside the viewport."""
    size = page.viewport_size
    for pill, topic in ((3, 'help.mission_type.deliver'), (2, 'help.head.actions.start_mission')):
        page.locator('.pill').nth(pill).click()
        button = page.locator(f'button.hint[data-topic="{topic}"]').first
        button.scroll_into_view_if_needed()
        button.click()
        popover = page.locator('#help-pop')
        try:
            expect(popover).to_be_visible()
            expect(popover).to_contain_text(t[f'{topic}.what'])
            box = popover.bounding_box()
            if not box or box['x'] < 0 or box['y'] < 0 or box['x'] + box['width'] > size['width']                     or box['y'] + box['height'] > size['height']:
                failures.append(f'{lang}: help popover {topic} leaves the viewport: {box}')
        except AssertionError as error:
            failures.append(f'{lang}: help popover {topic} not shown: {error}')
        if topic.startswith('help.head'):
            page.screenshot(path=str(shots / f'atelier-help-{lang}.png'))
        page.keyboard.press('Escape')


def check_stock(page, t: dict, lang: str, path: Path, voice_id: str, shots: Path, failures: list[str]) -> None:
    """E22-T12 and the simpler [trade] and [note] panels: a reward set to "Often"; a meeting point ticked among the
    voice's places (after the way to the Places panel), arrival, visits and hours picked, stock items ticked in the
    item list and added, one replaced and one removed, what the voice accepts (a category, an item), a lot made and used by the stock line, the margin in percent; the note's text with its
    live count, the common base stated and a themed loot list; saved and accepted by the game reader (screenshots
    atelier-rewards-fr.png, atelier-items-fr.png, atelier-trade-fr.png, atelier-note-fr.png)."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    show_text(page, t, True)
    page.locator('.pill').nth(4).click()                                   # rewards
    preview = page.locator('.sheet-preview')
    reward = page.locator('.card.reward').first
    expect(reward.locator('button[data-chance="normal"]')).to_have_attribute('aria-pressed', 'true')
    reward.locator('button[data-chance="often"]').click()
    expect(preview).to_contain_text(re.compile(r'pool=cache:[a-z_]+:4, lesson:[A-Za-z]+:2'))
    expect(reward.locator('.chance')).to_contain_text(t['rewards.one_in'].replace('{n}', '2'))
    print(f'{lang}: reward set to "{t["chance.often"]}": weight 4 in the sheet, "{t["rewards.one_in"]}" shown')
    page.screenshot(path=str(shots / f'atelier-rewards-{lang}.png'), full_page=True)
    page.locator('.pill').nth(2).click()                                   # the trade action, as the panel says
    page.locator('.check', has_text=t['action.propose_trade']).locator('input').check()
    page.locator('.pill').nth(4).click()
    trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
    trade.locator(':scope > summary').click()
    trade.get_by_label(t['advanced.trade.enable']).check()
    # meeting point: "New place…" in the list (a shared spot), made without leaving the voice and ticked
    make_place(page, trade, t, 'Quai du lac', ('10620', '9310', '0'), points=True)
    trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
    expect(trade).to_have_attribute('open', '')
    expect(trade.locator('.place-checks .check', has_text='Quai du lac').locator('input')).to_be_checked()
    expect(preview).to_contain_text('landing=quai_du_lac')
    print(f'{lang}: meeting point made with "{t["places.new_option"]}" in the trade panel, ticked')
    trade.locator('label.choice-card[data-value="boat"]').click()
    expect(preview).to_contain_text('arrival=boat')
    trade.locator('[data-scale="scale.trade.every_days"] button[data-step="weekly"]').click()
    trade.get_by_label(t['trade.hours_start'], exact=True).fill('02:00')
    trade.get_by_label(t['trade.hours_end'], exact=True).fill('04:00')
    expect(preview).to_contain_text('every_days=7')
    expect(preview).to_contain_text('hours=02:00-04:00')

    # stock (user 2026-11-16: no item name typed anywhere): "Ajouter des objets" opens the list of the items a trader
    # can sell (E22-T17), searched by name and filtered by category, two items ticked then added; each line shows the
    # item's name (no weight), its Module.Type only as tooltip; a line replaced from the same list, a line removed
    stock_row = row_of(trade, page, t['key.trade.item'])
    stock_row.get_by_role('button', name=t['trade.add_sold'], exact=True).click()
    dialog = page.locator('dialog.item-browser.multi')
    expect(dialog).to_be_visible()
    expect(dialog.locator('.browser-note')).to_have_text(t['browser.sellable_only'])
    search = dialog.get_by_label(t['browser.search'], exact=True)
    options = dialog.locator('[role=option]')
    search.fill('hache')
    expect(dialog.locator('.browser-list li.muted')).to_have_text(t['browser.none'])
    expect(options).to_have_count(0)
    search.fill('bandage')
    expect(options.first).to_have_attribute('data-type', 'Base.Bandage')
    expect(options.first).to_have_attribute('title', 'Base.Bandage')
    if dialog.locator('.browser-list').inner_text().count('Base.'):
        failures.append(f'{lang}: the item list shows Module.Type on screen')
    found = [options.nth(i).get_attribute('data-type') for i in range(options.count())]
    if any(f not in atelier_catalog()['sellable_set'] for f in found):
        failures.append(f'{lang}: the stock list offers items a trader cannot sell: {found}')
    options.first.click()
    expect(options.first.locator('input[type=checkbox]')).to_be_checked()
    expect(dialog.locator('.browser-selected')).to_have_text(t['browser.selected'].replace('{n}', '1'))
    page.screenshot(path=str(shots / f'atelier-items-{lang}.png'))
    dialog.get_by_label(t['browser.category'], exact=True).select_option('Food')
    search.fill('whisky')
    expect(options.first).to_have_attribute('data-type', 'Base.Whiskey')
    options.first.click()
    add = dialog.locator('.browser-add')
    expect(add).to_have_text(t['browser.add_selected'].replace('{n}', '2'))
    add.click()
    expect(dialog).to_have_count(0)
    expect(preview).to_contain_text('item=Base.Bandage:1')
    expect(preview).to_contain_text('item=Base.Whiskey:1')
    lines = trade.locator('.stock-line')
    expect(lines).to_have_count(2)
    first = lines.first.locator('.item-choice')
    expect(first.locator('.item-name')).to_have_text('Bandage')
    expect(first).to_have_attribute('title', 'Base.Bandage')
    if re.search(r'\bkg\b', trade.inner_text()):
        failures.append(f'{lang}: a weight is still shown in the trade panel')
    if trade.locator('.stock-line input[type=text], .stock-line input:not([type])').count():
        failures.append(f'{lang}: a stock line still has a text field')
    print(f'{lang}: "hache" -> nothing (an axe has no price); "bandage" + "Nourriture"/"whisky" ticked and added '
          f'({", ".join(found[:3])}... all sellable): 2 lines, "Bandage", no weight, type in the tooltip only')
    lines.nth(1).locator('.item-choice').click()                           # replace: the same list, single choice
    single = page.locator('dialog.item-browser:not(.multi)')
    expect(single).to_be_visible()
    single.get_by_label(t['browser.search'], exact=True).fill('vodka')
    single.get_by_label(t['browser.search'], exact=True).press('Enter')
    expect(single).to_have_count(0)
    expect(preview).to_contain_text('item=Base.Vodka:1')
    expect(preview).not_to_contain_text('Base.Whiskey')
    second = trade.locator('.lines .line', has=page.locator('.stock-line')).nth(1)
    second.get_by_role('button', name=t['field.remove'], exact=True).click()                 # remove
    expect(lines).to_have_count(1)
    expect(preview).not_to_contain_text('Base.Vodka')
    print(f'{lang}: line 2 replaced from the list (whisky -> vodka, Enter), then removed')
    lines.first.get_by_label(t['field.min'], exact=True).fill('2')
    lines.first.get_by_label(t['field.max'], exact=True).fill('6')
    expect(preview).to_contain_text('item=Base.Bandage:2-6')
    print(f'{lang}: stock line item=Base.Bandage:2-6')
    # what the voice accepts (E23-T06): a whole category ticked (only those with an item a trader can take), an item
    # added from the list of sellable items
    accept = row_of(trade, page, t['key.trade.accept'])
    cats = accept.locator('.accept-categories .check')
    expect(accept.locator('.check[data-value=cash]')).to_contain_text(t['category.cash'])
    if accept.locator('.check[data-value=ammo], .check[data-value=tools]').count():
        failures.append(f'{lang}: the accepted categories offer a category without any item a trader can take')
    accept.locator('.check[data-value=cash] input').check()
    expect(preview).to_contain_text('accept=cash')
    accept.get_by_role('button', name=t['trade.add_taken'], exact=True).click()
    dialog = page.locator('dialog.item-browser.multi')
    dialog.get_by_label(t['browser.search'], exact=True).fill('antibio')
    expect(options.first).to_have_attribute('data-type', 'Base.Antibiotics')
    options.first.click()
    dialog.locator('.browser-add').click()
    expect(preview).to_contain_text('accept=Base.Antibiotics')
    expect(accept.locator('.accept-line .item-choice').first).to_have_attribute('title', 'Base.Antibiotics')
    print(f'{lang}: accepts: {cats.count()} categories offered, "{t["category.cash"]}" ticked, Antibiotics added '
          '(accept=cash, accept=Base.Antibiotics)')
    # a paquet (E24-T02): its name typed, its id made and hidden, its items from the list, its total as steppers
    lots = row_of(trade, page, t['key.trade.group'])
    lots.get_by_label(t['lot.name'], exact=True).fill('Médicaments')
    lots.get_by_role('button', name=t['lot.add']).click()
    expect(preview).to_contain_text('group=medicaments:1-3')
    paquet = trade.locator('article.paquet')
    expect(paquet.locator('.paquet-name')).to_have_value('Medicaments')
    paquet.get_by_role('button', name=t['lot.add_items']).click()
    dialog = page.locator('dialog.item-browser.multi')
    dialog.get_by_label(t['browser.search'], exact=True).fill('pile')
    dialog.locator('[role=option]:not(.taken)').first.click()
    dialog.locator('.browser-add').click()
    expect(preview).to_contain_text(re.compile(r'item=Base\.[A-Za-z]+:medicaments'))
    paquet.get_by_role('button', name=f"{t['lot.kinds']} +", exact=True).click()
    expect(preview).to_contain_text('group=medicaments:1-3:1')
    print(f'{lang}: paquet "Médicaments" made (group=medicaments:1-3:1), an item added from the list')
    margin = row_of(trade, page, t['key.trade.margin'])
    margin.locator('label.choice-card[data-value="greedy"]').click()
    expect(preview).to_contain_text('margin=0.30-0.80')
    margin.locator('details.fold > summary').click()
    margin.get_by_label(t['field.min'], exact=True).fill('10')
    margin.get_by_label(t['field.max'], exact=True).fill('40')
    expect(preview).to_contain_text('margin=0.10-0.40')
    print(f'{lang}: margin "{t["scale.trade.margin.greedy"]}" -> margin=0.30-0.80, exact value 10-40 % -> 0.10-0.40')
    trade.evaluate("d => d.scrollIntoView({block: 'start'})")
    page.screenshot(path=str(shots / f'atelier-trade-{lang}.png'))

    note = page.locator('details.fold', has_text=t['advanced.note.enable'])
    note.locator(':scope > summary').click()
    note.get_by_label(t['advanced.note.enable']).check()
    line = note.get_by_label(t['note.line'].replace('{n}', '1'), exact=True)
    line.fill('Mae écoute sur ')
    note.get_by_role('button', name=t['freq.add']).first.click()
    line.press('End')
    line.type(' MHz')
    counter = note.locator('.note-line .counter').first
    expect(counter).to_have_text(t['note.bytes'].replace('{n}', '22').replace('{max}', '40'))
    note.get_by_role('button', name=t['note.add_line']).click()
    long_line = note.get_by_label(t['note.line'].replace('{n}', '2'), exact=True)
    long_line.fill('Une ligne bien trop longue pour tenir sur la note')
    expect(note.locator('.note-line .counter').nth(1)).to_have_class(re.compile(r'\bover\b'))
    long_line.fill('Passe le soir')
    expect(preview).to_contain_text('text=Mae écoute sur %1 MHz')
    # E24-T04: the AI proposes the second line; the frequency shows as the word on screen, the sheet holds %1
    sheet_line = fake_llm.WORKSHOP_SUGGEST_TEXTS['note_line'].replace('{frequency}', '%1')
    check_propose(long_line, note.locator('.note-line').nth(1).locator('button.propose[data-field="note_line"]'),
                  sheet_line.replace('%1', t['freq.word']))
    expect(preview).to_contain_text('text=' + sheet_line)
    print(f'{lang}: note line proposed, the frequency as a word on screen and %1 in the sheet')
    expect(note).to_contain_text(t['advanced.note.help'])
    expect(note.locator('section.question h4', has_text=t['note.q_also'])).to_be_visible()
    if note.get_by_text(t['section.advanced'], exact=True).count():
        failures.append(f'{lang}: the note of a new voice shows the advanced item and key')
    loot = note.locator('.row').filter(has=page.get_by_text(t['key.note.loot'], exact=True))
    # E24-T03: themed places picked in the browser (kind, search word, tick), never typed; the line is read-only.
    loot.locator('button.add-places').click()
    dialog = page.locator('dialog.item-browser.multi')
    kinds = dialog.locator('select.browser-category option').count()
    dialog.locator('select.browser-category').select_option('home')
    dialog.get_by_label(t['lootbrowser.search'], exact=True).fill('kitchen dry')
    dialog.locator('[role=option][data-type="KitchenDryFood"]').click()
    dialog.locator('.browser-add').click()
    if loot.locator('input[type=text]').count():
        failures.append(f'{lang}: a themed place line can still be typed')
    expect(loot.locator('.loot-name').first).to_have_text('Kitchen dry food')
    expect(loot.locator('.loot-name').first).to_have_attribute('title', 'KitchenDryFood')
    loot.locator('button[data-chance="often"]').click()
    expect(preview).to_contain_text('loot=KitchenDryFood:4')
    if kinds < 6:
        failures.append(f'{lang}: the place browser offers {kinds - 1} kinds (5 expected)')
    print(f'{lang}: note text with its count (22 / 40, too long line flagged), common base stated, '
          f'themed place picked in the browser ({kinds - 1} kinds, no typing): loot=KitchenDryFood:4')
    note.evaluate("d => d.scrollIntoView({block: 'start'})")
    page.screenshot(path=str(shots / f'atelier-note-{lang}.png'))
    page.locator('#save').click()
    expect(page.locator('.toast').last).to_contain_text(t['code.voice_saved'])
    text = path.read_text(encoding='utf-8')
    verdict = game_reads(text, voice_id, working_places(path.parent))
    print(f'{lang}: voice with trade and note saved, game reader: {verdict[0]} '
          f'{verdict[1] if verdict[0] != "OK" else ""}'.rstrip())
    if verdict[0] != 'OK':
        failures.append(f'{lang}: game reader refused the trade and note: {verdict[1]}\n{text}')
    # a shipped voice: its note's own item and text key stay in the advanced settings, its paquets and stock shown
    page.locator('.voice', has_text='Boone Tackett').first.click()
    page.locator('.pill').nth(4).click()
    note = page.locator('details.fold', has_text=t['advanced.note.enable'])
    note.locator(':scope > summary').click()
    expect(note.get_by_text(t['note.own_item'], exact=True)).to_be_visible()
    advanced = note.locator('details.fold', has_text=t['section.advanced'])
    advanced.locator(':scope > summary').click()
    expect(advanced.locator('.item-choice')).to_have_attribute('title', re.compile(r'^RadioSurvivor\.Note'))
    trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
    trade.locator(':scope > summary').click()
    expect(trade.locator('article.paquet .paquet-name').first).to_have_value('Alcohol')
    expect(trade.locator('.stock-line').first.locator('.item-name')).not_to_have_text('')
    expect(page.locator('.dirty')).to_have_text(t['editor.saved'])
    print(f'{lang}: shipped voice: note item and key in "{t["section.advanced"]}", paquet "Alcohol" shown, '
          'nothing changed by opening it')


def row_of(scope, page, label: str):
    """The form row of a key, by the text of its label."""
    return scope.locator('.row', has=page.locator(':scope > .lab label', has_text=label)).first


def boxes(cells) -> list[tuple[int, int]]:
    """(x, width) of each cell, rounded to the pixel (an empty cell has no height: its box is read by the page)."""
    return [tuple(cells.nth(i).evaluate('e => { const r = e.getBoundingClientRect(); '
                                        'return [Math.round(r.x), Math.round(r.width)]; }'))
            for i in range(cells.count())]


def atelier_catalog() -> dict:
    """catalog.json of the page, with the set of the sellable items."""
    data = json.loads((ATELIER / 'catalog.json').read_text(encoding='utf-8'))
    data['sellable_set'] = set(data.get('sellable', []))
    return data


def reload(page) -> None:
    """Reloads the page, leaving an unsaved voice if one is open (the page asks before leaving it), then shows the Voices
    tab (the dashboard comes first, without the voice list)."""
    def accept(dialog):
        dialog.accept()
    page.on('dialog', accept)
    try:
        page.reload()
    finally:
        page.remove_listener('dialog', accept)
    page.locator('#tab-voices').click()


def check_status_and_confirm(page, t: dict, lang: str, working: Path, failures: list[str]) -> None:
    """E22-T17: a copy of Walt the game wrote from an older version of the mod (its fingerprint remembered) shows the
    "older version" state with its tooltip, in the list and on the badge; the removal asked names the voice by its
    name, not its id. The working folder is put back as it was."""
    walt = working / 'walt.txt'
    shipped = walt.read_bytes()
    older = shipped.decode('utf-8').replace('\n', '\n# an older version of the mod\n', 1)
    prints = working.parent / atelier_server.FINGERPRINTS
    walt.write_text(older, encoding='utf-8', newline='\n')
    prints.write_text(f'RSFP1\nwalt.txt {atelier_server.fingerprint(older)}\n', encoding='utf-8', newline='\n')
    try:
        reload(page)
        item = page.locator('.voice', has_text='Walt Hensley').first
        expect(item.locator('.dot.outdated')).to_have_count(1)
        expect(item).to_have_attribute('title', t['status.outdated.help'])
        item.click()
        badge = page.locator('#main .toolbar .badge.outdated')
        expect(badge).to_have_text(t['status.outdated'])
        expect(badge).to_have_attribute('title', t['status.outdated.help'])
        page.locator('#main .toolbar').get_by_role('button', name=t['editor.action_remove']).click()
        notice = page.locator('.notice[role=alertdialog]')
        expect(notice).to_contain_text(t['confirm.remove'].split('{name}')[0] + 'Walt Hensley')
        notice.get_by_role('button', name=t['dialog.cancel']).click()
        print(f'{lang}: older copy of Walt -> "{t["status.outdated"]}" with its tooltip; removal asked for "Walt Hensley"')
    except AssertionError as e:
        failures.append(f'{lang}: older version or confirm name: {e}')
    finally:
        walt.write_bytes(shipped)
        prints.unlink()
        reload(page)


def check_stock_grid(page, trade, t: dict, lang: str, width: int, failures: list[str]) -> None:
    """Every stock line of the shipped voice on the same grid: the item and "between ... and ..." cells of two lines
    share their x and width."""
    lines = trade.locator('.stock-line')
    cells = {name: (boxes(lines.nth(0).locator(f':scope > {sel}')), boxes(lines.nth(1).locator(f':scope > {sel}')))
             for name, sel in (('item', '.item-choice'), ('range', '.range'))}
    print(f'{lang}: stock grid at {width} px, (x, width) line 1 / line 2: '
          + '; '.join(f'{k} {a} / {b}' for k, (a, b) in cells.items()))
    for name, (a, b) in cells.items():
        if not a or a != b:
            failures.append(f'{lang}: stock cells "{name}" not aligned at {width} px: {a} != {b}')


def check_item_browser(page, t: dict, lang: str, name: str, shots: Path, failures: list[str]) -> None:
    """User 2026-11-15, 2026-11-16: the stock of a shipped voice (Boone) is a grid whose columns line up at 1280 and
    800 px (screenshot atelier-stock-aligned-fr.png); "Ajouter des objets" opens the item list, filtered by a category
    and searched in French: an item already in the stock is shown as such and cannot be ticked, two items ticked (a
    click, Enter) stay ticked across searches (screenshot atelier-item-browser-fr.png); Escape adds nothing; reopened,
    "Ajouter la sélection" adds the two ticked items."""
    trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
    stock = trade.locator('.lines', has=page.locator('.stock-line'))
    show_text(page, t, False)                                                  # the form alone, full width
    if page.locator('#try-open').get_attribute('aria-pressed') == 'true':
        page.locator('#try-open').click()
    for width in (1280, 800):
        page.set_viewport_size({'width': width, 'height': 900})
        check_stock_grid(page, trade, t, lang, width, failures)
        scroll = page.evaluate('document.documentElement.scrollWidth')
        if scroll > width:
            failures.append(f'{lang}: horizontal scroll at {width} px on the stock ({scroll} px)')
    page.set_viewport_size({'width': 1280, 'height': 900})
    stock.scroll_into_view_if_needed()
    stock.screenshot(path=str(shots / f'atelier-stock-aligned-{lang}.png'))
    before = trade.locator('.stock-line').count()
    stock_row = row_of(trade, page, t['key.trade.item'])
    stock_row.get_by_role('button', name=t['trade.add_sold'], exact=True).click()
    dialog = page.locator('dialog.item-browser.multi')
    expect(dialog).to_be_visible()
    expect(dialog.locator('.browser-note')).to_have_text(t['browser.sellable_only'])
    total_all = dialog.locator('[role=option]').count()
    dialog.get_by_label(t['browser.category'], exact=True).select_option('Food')
    expect(dialog.locator('.browser-count')).not_to_have_text(t['browser.count'].replace('{n}', str(total_all)))
    search = dialog.get_by_label(t['browser.search'], exact=True)
    search.fill('whisky')
    first = dialog.locator('[role=option]').first
    expect(first).to_have_attribute('data-type', 'Base.Whiskey')
    expect(first.locator('.b-name')).to_have_text('Bouteille de whisky')
    expect(first.locator('.b-cat')).to_have_text('Nourriture')
    expect(first).to_have_class(re.compile(r'\btaken\b'))                 # already in Boone's stock: not twice
    expect(first.locator('.b-pick')).to_have_text(t['browser.taken'])
    first.click(force=True)                                                 # aria-disabled: nothing happens
    expect(dialog.locator('.browser-add')).to_be_disabled()
    search.fill('chili')
    first = dialog.locator('[role=option]').first
    expect(first).to_have_attribute('data-type', 'Base.CannedChili')
    first.click()
    search.fill('riz')
    expect(dialog.locator('[role=option]').first).to_have_attribute('data-type', 'Base.Rice')
    search.press('Enter')                                                    # keyboard: ticks the first match
    expect(dialog.locator('.browser-selected')).to_have_text(t['browser.selected'].replace('{n}', '2'))
    search.fill('chili')
    expect(dialog.locator('[role=option]').first.locator('input')).to_be_checked()   # the ticks survive a new search
    dialog.locator('[role=option]').first.hover()
    page.screenshot(path=str(shots / f'atelier-item-browser-{lang}.png'))
    print(f'{lang}: browser "Nourriture": whisky shown "{t["browser.taken"]}", chili clicked, riz by Enter: 2 ticked')
    page.keyboard.press('Escape')                                            # Escape: nothing added
    expect(dialog).to_have_count(0)
    expect(trade.locator('.stock-line')).to_have_count(before)
    stock_row.get_by_role('button', name=t['trade.add_sold'], exact=True).click()
    for word in ('chili', 'riz'):
        search.fill(word)
        dialog.locator('[role=option]').first.click()
    dialog.locator('.browser-add').click()
    expect(dialog).to_have_count(0)
    added = trade.locator('.stock-line').count() - before
    show_text(page, t, True)
    text = page.locator('.sheet-preview')
    expect(text).to_contain_text('item=Base.CannedChili:1')
    expect(text).to_contain_text('item=Base.Rice:1')
    print(f'{lang}: Escape added nothing; reopened, 2 ticked and "{t["browser.add_selected"]}": {added} new stock lines')
    if added != 2:
        failures.append(f'{lang}: the item browser added {added} stock lines instead of 2')
    # leave Boone without saving: the shipped voice stays as it is
    page.locator('.voice', has_text=name).first.click()
    page.get_by_role('button', name=t['confirm.leave_yes']).click()


SURVEYS = ('# RadioSurvivor places recorded for the voice workshop\n'
           'time=2026-11-15 10:00:00\tgame=1993-07-09 08:30\tby=Kate Smith\tat=10600,9300,0\troom=kitchen\t'
           'building=10590,9290,10620,9310\n'
           'time=2026-11-15 10:05:00\tgame=1993-07-09 08:41\tby=Kate Smith\tat=10612,9307,0\t'
           'containers=bin:trash_01_0\n')


def check_surveys(page, t: dict, lang: str, working: Path, survey_file: Path, shots: Path, failures: list[str]) -> None:
    """E22-T08, E25-T03: the places recorded in game listed in the Places tab, one made a shared place."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    page.locator('#tab-places').click()
    page.locator('#places-home').click()                                   # the tab's home: recorded in game
    items = page.locator('li.survey')
    expect(items).to_have_count(2)
    expect(items.first).to_contain_text('10612, 9307, 0')                  # newest first: the dumpster
    expect(items.nth(1)).to_contain_text('Kitchen')
    places_before = page.locator('#places .place-item').count()
    items.first.get_by_role('button', name=t['surveys.add']).click()
    ask = page.locator('.surveys-block .notice')
    label = ask.get_by_label(t['places.label'], exact=True)
    expect(label).to_have_value('Bin')
    label.fill("Benne de l'église")
    ask.get_by_role('button', name=t['places.add_ok']).click()
    expect(page.locator('#places .place-item')).to_have_count(places_before + 1)
    expect(page.locator('li.survey').first).to_contain_text(t['surveys.known'])
    page.locator('li.survey').first.scroll_into_view_if_needed()
    page.screenshot(path=str(shots / f'atelier-surveys-{lang}.png'), full_page=True)
    page.locator('#places .place-item[data-id="benne_de_l_eglise"]').click()   # its id made from its name
    card = page.locator('.card.place[data-place="benne_de_l_eglise"]')
    expect(card.get_by_label(t['places.label'], exact=True)).to_have_value("Benne de l'église")
    for axis, value in zip(('x', 'y', t['places.floor']), ('10612', '9307', '0')):
        expect(card.get_by_label(axis, exact=True)).to_have_value(value)
    text = working_places(working)
    placed = re.search(r"\[place [a-z0-9_]+\]\nlabel=Benne de l'église\nat=10612,9307,0\n", text)
    try:
        persona_store.parse_places_lines(persona_store.split_lines(text))
        reader = 'OK'
    except persona_store.PersonaError as err:
        reader = str(err)
    print(f'{lang}: places recorded in game: 2 listed newest first, "{t["surveys.add"]}" made a shared place at '
          f'10612,9307,0: {bool(placed)}, bridge reader: {reader}')
    if not placed:
        failures.append(f'{lang}: place from the survey missing in the places file\n{text}')
    if reader != 'OK':
        failures.append(f'{lang}: the bridge reader refused the places file: {reader}')
    if survey_file.read_text(encoding='utf-8') != SURVEYS:
        failures.append(f'{lang}: the survey file was changed by the workshop')
    page.locator('#tab-voices').click()


SMOKE_PASSWORD = 'smoke test password'      # never a real one: the gate is built here, bridge/.env is not read


def check_login(browser, store, locale: str, lang: str, shots: Path, failures: list[str]) -> None:
    """E22-T15, network mode (NetworkGate served on the loopback, which logs in like any client): the page sends to
    the login page; a wrong password is said wrong, the right one opens the workshop with a logout button that sends
    back to the login page; five failures then lock with the seconds to wait, in the page language."""
    t = strings(lang)
    logs: list[str] = []
    gate = atelier_server.NetworkGate(atelier_auth.Authenticator(SMOKE_PASSWORD, logs.append))
    server = atelier_server.bind(store, 0, ATELIER, atelier_server.mod_version(SHIPPED), logs.append, gate=gate)
    atelier_server.start(server)
    context = browser.new_context(locale=locale, viewport={'width': 800, 'height': 700})
    page = context.new_page()
    errors: list[str] = []
    page.on('console', lambda m: errors.append(m.text) if m.type == 'error' else None)
    page.on('pageerror', lambda e: errors.append(str(e)))
    try:
        page.goto(server.url)
        expect(page).to_have_url(re.compile(r'/login\.html$'))
        expect(page.locator('h2')).to_have_text(t['login.heading'])
        password = page.get_by_label(t['login.password'], exact=True)
        password.fill('wrong guess')
        page.locator('#login-submit').click()
        expect(page.locator('.login-message')).to_have_text(t['code.bad_password'])
        page.screenshot(path=str(shots / f'atelier-login-{lang}.png'))
        password.fill(SMOKE_PASSWORD)
        page.locator('#login-submit').click()
        expect(page.locator('h1')).to_have_text(t['app.title'])
        expect(page.locator('#logout')).to_have_text(t['app.logout'])
        page.locator('#logout').click()
        expect(page).to_have_url(re.compile(r'/login\.html$'))
        expect(page.locator('h2')).to_have_text(t['login.heading'])
        for _ in range(5):
            password.fill('wrong guess')
            page.locator('#login-submit').click()
            expect(page.locator('#login-submit')).to_be_enabled()
        password.fill(SMOKE_PASSWORD)
        page.locator('#login-submit').click()
        expect(page.locator('.login-message')).to_have_text(t['login.locked'].replace('{seconds}', '60'))
        print(f'{lang}: login page, wrong password, logout and lock: OK; journal lines: {len(logs)}')
    except AssertionError as err:
        failures.append(f'{lang}: login: {err}')
    finally:
        context.close()
        server.shutdown()
        server.server_close()
    if any(SMOKE_PASSWORD in line or 'wrong guess' in line for line in logs):
        failures.append(f'{lang}: a password reached the journal')
    errors = [e for e in errors if '401 (Unauthorized)' not in e and '429 (Too Many Requests)' not in e]
    if errors:
        failures.append(f'{lang}: login console errors: {errors}')


def run(shots: Path) -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        working = Path(tmp) / 'personas'
        shutil.copytree(SHIPPED, working, ignore=shutil.ignore_patterns('_*'))
        store = atelier_server.VoiceStore(working, SHIPPED)
        console = Path(tmp) / 'console.txt'        # missing until the first refusal: tolerated
        running = threading.Event()
        running.set()
        survey_file = Path(tmp) / place_surveys.FILE_NAME   # next to the working folder, as the game writes it
        survey_file.write_text(SURVEYS, encoding='utf-8', newline='\n')
        live = atelier_server.Live(radio_bridge.LOG_BUFFER, game_console.GameConsole(console, radio_bridge.LOG_BUFFER),
                                   running.is_set, surveys=place_surveys.SurveyFile(survey_file))
        server = atelier_server.bind(store, 0, ATELIER, atelier_server.mod_version(SHIPPED), print, live=live)
        atelier_server.start(server)
        fake, port = start_fake()
        radio_bridge.TOKEN_USAGE = radio_bridge.TokenUsageLog(Path(tmp) / 'token_usage.jsonl')
        ai = radio_bridge.workshop_ai({'OPENAI_BASE_URL': f'http://127.0.0.1:{port}/v1', 'OPENAI_MODEL': 'fake',
                                       'OPENAI_KEY': 'fake'}, store.shared_places)
        try:
            with sync_playwright() as pw:
                browser = pw.chromium.launch()
                for locale, lang in LOCALES:
                    t = strings(lang)
                    voice_id, name = f'smoke{lang}', f'Smoke{lang} Tester'          # the id: the first name
                    context = browser.new_context(locale=locale, viewport={'width': 1280, 'height': 900})
                    page = context.new_page()
                    errors: list[str] = []
                    page.on('console', lambda m, errors=errors: errors.append(m.text) if m.type == 'error' else None)
                    page.on('pageerror', lambda e, errors=errors: errors.append(str(e)))
                    live.ai = ai if lang == 'fr' else None
                    page.goto(server.url)
                    expect(page.locator('h1')).to_have_text(t['app.title'])
                    check_dashboard(page, t, lang, shots, failures)
                    create_voice(page, t, voice_id, name)
                    path = working / f'{voice_id}.txt'
                    text = path.read_text(encoding='utf-8') if path.is_file() else ''
                    verdict = game_reads(text, voice_id, working_places(working)) if text else ('MISSING', '')
                    print(f'{lang}: {path.name} {"written" if text else "missing"}, game reader: {verdict[0]} '
                          f'{verdict[1] if verdict[0] != "OK" else ""}'.rstrip())
                    if verdict[0] != 'OK':
                        failures.append(f'{lang}: game reader refused the sheet: {verdict[1]}\n{text}')
                    check_simple_sheet(text, lang, failures)
                    if '\nradio=tactical\n' not in text or '\nfrequency=' in text:   # E24-T01: the card picked last
                        failures.append(f'{lang}: the sheet should hold radio=tactical and no frequency=\n{text}')
                    exported = page.request.get(server.url.rstrip('/') + page.locator('a[download]').get_attribute('href'))
                    if exported.text() != text:
                        failures.append(f'{lang}: export differs from the saved file')
                    page.locator('input[type=file]').set_input_files(files=[{
                        'name': f'{voice_id}.txt', 'mimeType': 'text/plain', 'buffer': text.encode('utf-8')}])
                    page.locator('.notice').get_by_role('button', name=t['import.as_new']).click()
                    expect(page.locator('.toast')).to_contain_text(t['code.voice_imported'])
                    copy = working / f'{voice_id}_2.txt'                    # the next free id, nothing typed
                    imported = copy.is_file() and copy.read_text(encoding='utf-8') == text.replace(
                        f'id={voice_id}\n', f'id={voice_id}_2\n')
                    print(f'{lang}: export identical: {exported.text() == text}, import under a new id: {imported}')
                    if not imported:
                        failures.append(f'{lang}: import with a new id failed')
                    page.locator('.voice', has_text=name).first.click()   # the original, before its copy
                    page.locator('.pill').nth(3).click()                    # missions step for the screenshot
                    page.screenshot(path=str(shots / f'atelier-{lang}.png'), full_page=True)
                    if lang == 'fr':
                        check_help(page, t, lang, shots, failures)
                    page.set_viewport_size({'width': 800, 'height': 900})
                    width = page.evaluate('document.documentElement.scrollWidth')
                    print(f'{lang}: page width at 800 px viewport = {width}')
                    if width > 800:
                        failures.append(f'{lang}: horizontal scroll at 800 px ({width} px)')
                    check_live(page, t, lang, voice_id, name, text, console, running, shots, failures)
                    check_paste(page, t, lang, working, failures)
                    check_places(page, t, lang, name, working, shots, failures)
                    check_ai(page, t, lang, path, shots, failures)
                    if lang == 'fr':
                        check_stock(page, t, lang, path, voice_id, shots, failures)
                        check_item_browser(page, t, lang, name, shots, failures)
                        check_surveys(page, t, lang, working, survey_file, shots, failures)
                    check_status_and_confirm(page, t, lang, working, failures)
                    errors = [e for e in errors if '409 (Conflict)' not in e]   # the import conflict, expected
                    if errors:
                        failures.append(f'{lang}: console errors: {errors}')
                    context.close()
                    check_login(browser, store, locale, lang, shots, failures)
                browser.close()
        finally:
            stop(fake)
            server.shutdown()
            server.server_close()
    for failure in failures:
        print('FAIL', failure)
    print(f'summary: {"OK" if not failures else "FAILED"} ({len(LOCALES)} locales, {len(failures)} failure(s))')
    return 1 if failures else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--shots', type=Path, default=Path(tempfile.gettempdir()),
                        help='folder of the screenshots atelier-fr.png, atelier-en.png, atelier-verdict-fr.png '
                             'and atelier-journal-fr.png')
    args = parser.parse_args()
    args.shots.mkdir(parents=True, exist_ok=True)
    sys.exit(run(args.shots))
