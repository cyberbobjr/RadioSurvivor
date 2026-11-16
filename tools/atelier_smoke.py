"""Browser smoke test of the voice workshop (E22-T03): the real page in Chromium, French then English.

    python RadioSurvivor/tools/atelier_smoke.py [--shots <folder>]

Starts bridge/atelier_server.py on a free port over a temporary working folder (a copy of the shipped sheets; the
mod's folder is only read), opens the page with the locale fr-FR then en-US, creates a voice through the five-step
assistant (name, band, an allowed action, two places, a deliver mission with its dead drop, a barricade mission after it,
a reward), saves it, and checks that the file exists and that the real game reader (RS_Persona.lua in lupa) accepts
it. Exports it (same text) and imports it back, which asks for a new id. Then reopens it, looks at the page at 800 px wide (no horizontal scroll) and takes a screenshot per language.
Live part (E22-T04, E22-T10), in French: a fake game console refuses the voice at its frequency line and the bridge logs
a line through radio_bridge.log: red mark in the list, banner with the reason, button to the "where" step, the Journal
tab shows both lines and filters them (screenshots atelier-verdict-fr.png, atelier-journal-fr.png). In English, the
bridge loop is said stopped: the Journal tab explains that only the game lines appear.
AI part (E22-T06), against the deterministic fake LLM (tools/fake_llm, never a paid model): in French, "Write it with
the AI" writes the personality and "Use it" replaces the prompt after the in-page confirm, "Suggest" fills a mission
story, "Try the voice" answers from the unsaved sheet and Reset empties it, the working file untouched (screenshot
atelier-ai-fr.png). In English the AI is said unavailable: the buttons are greyed with the configuration tooltip.
Chances, trade and note (E22-T12), in French: a reward set to "Often" is written with weight 4; the trade panel ticks
its meeting point among the voice's places (reached by its button when there is none), adds stock items from the item
list (no item name typed: search, category, ticks, "Ajouter la sélection"), shows each as its name and weight with its
Module.Type as tooltip only, replaces a line from the same list and removes one, ticks a category and adds an item to
what the voice accepts (E23-T06), makes a lot used by the stock line; the note panel counts the bytes of its text and
switches on the corpses; the voice is saved and accepted by the game reader (screenshots atelier-rewards-fr.png,
atelier-items-fr.png, atelier-trade-fr.png, atelier-note-fr.png).
Stock grid and item browser (user 2026-11-15), in French, on a shipped voice (Boone): a stock line taken from a lot
and a line with a number have their cells at the same x and width at 1280 and 800 px; "Ajouter des objets" opens the
item list, filtered by a category: an item already in the stock is shown as such, a click and Enter tick two items that
stay ticked across searches, Escape adds nothing, "Ajouter la sélection" adds them (screenshots atelier-stock-aligned-fr.png, atelier-item-browser-fr.png).
Sellable stock, older copies and confirmations (E22-T17): the trader's stock offers only the items a trader can sell
(an axe is not found, the browser says so); a copy of Walt the game wrote from an older version of the mod shows
"Ancienne version" / "Older version" with its tooltip; the removal asked names the voice, not its id.
Places recorded in game (E22-T08), in French: a fake survey file of the game (a kitchen, then a dumpster) is listed
newest first under the voice's places; "Ajouter à cette voix" asks the name prefilled from the dumpster, makes a place
at its square with the dead drop use ticked, the record then says it is one of her places; the voice is saved and
accepted by the game reader, the survey file untouched (screenshot atelier-surveys-fr.png).
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
sys.path.insert(0, str(ROOT / 'tests'))
import atelier_auth  # noqa: E402
import atelier_server  # noqa: E402
import game_console  # noqa: E402
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


def create_voice(page, t: dict, voice_id: str, name: str) -> None:
    page.locator('#new-voice').click()
    page.locator('#new-name').fill(name)
    page.locator('#new-id').fill(voice_id)
    page.locator('#new-create').click()
    expect(page.locator('.pill.on')).to_contain_text(t['step.who'])
    page.get_by_label(t['who.description'], exact=True).fill('A voice made by the smoke test')
    next_button = page.locator('#step-next')

    next_button.click()                                                    # 2: where and when (free band given)
    expect(page.locator('.pill.on')).to_contain_text(t['step.where'])
    page.get_by_role('button', name=t['where.add_hours']).click()

    next_button.click()                                                    # 3: personality
    expect(page.locator('.pill.on')).to_contain_text(t['step.personality'])
    page.locator('.check', has_text=t['action.start_mission']).locator('input').check()

    next_button.click()                                                    # 4: places and missions
    for label, at, uses in (('Old mill', ('10600', '9300', '0'), ('use.target', 'use.mark')),
                            ('Dumpster behind the mill', ('10610', '9305', '0'), ('use.drop',))):
        page.get_by_role('button', name=t['places.add']).click()
        page.locator('.notice').get_by_label(t['places.label'], exact=True).fill(label)
        page.locator('.notice').get_by_role('button', name=t['places.add_ok']).click()
        card = page.locator('details.fold').first.locator('.card').last
        expect(card.get_by_label(t['places.label'], exact=True)).to_have_value(label)
        map_link = card.locator('a.maplink')                               # Build 42 map: whole map, then the square
        expect(map_link).to_have_attribute('href', 'https://zomboidmap.com/')
        expect(map_link).to_have_text(t['map.home'])
        expect(card).to_contain_text(t['places.at_help'])
        for axis, value in zip(('x', 'y', 'z'), at):
            card.get_by_label(axis, exact=True).fill(value)
        expect(map_link).to_have_attribute('href', f'https://zomboidmap.com/#11/{at[0]}/{at[1]}/f{at[2]}')
        expect(map_link).to_have_text(t['map.open'])
        expect(map_link).to_have_attribute('target', '_blank')
        for use in uses:
            card.locator('.check', has_text=t[use]).locator('input').check()
    page.locator('.type-card', has_text=t['mission.deliver']).click()
    deliver = page.locator('.card.mission').last
    deliver.get_by_label(t['param.items'], exact=True).select_option('medical')
    deliver.get_by_label(t['field.min'], exact=True).fill('2')
    deliver.get_by_label(t['field.max'], exact=True).fill('4')
    deliver.get_by_label(t['mission.story'], exact=True).fill('Leave some bandages by the dumpster.')
    page.locator('.type-card', has_text=t['mission.barricade']).click()
    barricade = page.locator('.card.mission').last
    barricade.get_by_label(t['param.count'], exact=True).fill('4')
    barricade.get_by_label(t['mission.after'], exact=True).select_option('deliver')

    next_button.click()                                                    # 5: rewards
    page.locator('.type-card', has_text=t['reward.cache']).click()
    page.locator('.type-card', has_text=t['reward.lesson']).click()
    page.locator('#save').click()
    expect(page.locator('.toast')).to_contain_text(t['code.voice_created'])


def check_live(page, t: dict, lang: str, voice_id: str, name: str, sheet: str, console: Path, running, shots: Path,
               failures: list[str]) -> None:
    """E22-T04 and E22-T10 in the page: the game's verdict and the live journal."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    if lang == 'fr':
        line = next(i for i, text in enumerate(sheet.splitlines(), 1)
                    if text.startswith(('frequency_range=', 'frequencies=')))
        reason = "bad frequency range '150.0-140.0' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)"
        with console.open('a', encoding='utf-8', newline='') as handle:
            handle.write(f'LOG  : General      f:0> [batman_RadioSurvivor]     [RadioSurvivor] personas: ERROR: '
                         f'batman_RadioSurvivor/personas/{voice_id}.txt refused, line {line}: {reason}\n')
        radio_bridge.log(f'Smoke -> {voice_id} : hello from the smoke test')
        voice = page.locator('.voice', has_text=name).first
        expect(voice.locator('.gamebad')).to_be_visible(timeout=15000)
        voice.click()
        banner = page.locator('.verdict')
        expect(banner).to_contain_text(t['verdict.title'].replace('{line}', str(line)))
        expect(banner).to_contain_text(reason)
        expect(banner).to_contain_text(t['verdict.why.frequency'])
        page.locator('#verdict-go').click()
        expect(page.locator('.pill.on')).to_contain_text(t['step.where'])
        print(f'{lang}: refusal at line {line}: red mark, banner and jump to the where step shown')
        page.screenshot(path=str(shots / f'atelier-verdict-{lang}.png'), full_page=True)
        page.locator('#tab-journal').click()
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
    expect(page.locator('.journal-note').first).to_contain_text(t['journal.no_bridge'], timeout=10000)
    print(f'{lang}: bridge loop stopped: the journal says only game lines appear')
    running.set()
    page.locator('#tab-voices').click()


def check_ai(page, t: dict, lang: str, path: Path, shots: Path, failures: list[str]) -> None:
    """E22-T06 in the page: the AI panel, the story suggestion and the test conversation (fr), greyed buttons (en)."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    before = path.read_bytes()
    page.locator('.pill').nth(2).click()                                   # personality
    opener = page.locator('#ai-personality-open')
    if lang != 'fr':
        expect(opener).to_be_disabled()
        if opener.get_attribute('title') != t['ai.unavailable']:
            failures.append(f'{lang}: greyed AI button without the configuration tooltip')
        expect(page.locator('#try-open')).to_have_attribute('title', t['ai.unavailable'])
        print(f'{lang}: no AI configured: buttons greyed with the configuration tooltip')
        return
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
    card.get_by_role('button', name=t['ai.suggest']).click()
    expect(card.get_by_label(t['mission.story'], exact=True)).to_have_value(fake_llm.WORKSHOP_STORY_TEXT, timeout=15000)
    print(f'{lang}: mission story suggested')
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
    live count, the corpses switch and a loot list; saved and accepted by the game reader (screenshots
    atelier-rewards-fr.png, atelier-items-fr.png, atelier-trade-fr.png, atelier-note-fr.png)."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    page.get_by_role('button', name=t['editor.preview'], exact=True).click()
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
    trade.locator('summary').click()
    trade.get_by_label(t['advanced.trade.enable']).check()
    # meeting points: none yet -> the way to the Places panel, a place used as trade meeting, back and ticked
    expect(trade.locator('.warnline', has_text=t['trade.no_landing'])).to_be_visible()
    trade.locator('button.to-places').click()
    expect(page.locator('.pill.on')).to_contain_text(t['step.missions'])
    places = page.locator('details.fold').first
    expect(places).to_have_attribute('open', '')
    page.get_by_role('button', name=t['places.add']).click()
    page.locator('.notice').get_by_label(t['places.label'], exact=True).fill('Quai du lac')
    page.locator('.notice').get_by_role('button', name=t['places.add_ok']).click()
    card = places.locator('.card').last
    for axis, value in zip(('x', 'y', 'z'), ('10620', '9310', '0')):
        card.get_by_label(axis, exact=True).fill(value)
    card.locator('.check', has_text=t['use.landing']).locator('input').check()
    page.locator('.pill').nth(4).click()
    expect(trade).to_have_attribute('open', '')
    trade.locator('.checks.landing .check', has_text='Quai du lac').locator('input').check()
    expect(preview).to_contain_text('landing=quai_du_lac')
    print(f'{lang}: no meeting point -> "{t["trade.to_places"]}" -> place added -> ticked: landing=quai_du_lac')
    trade.get_by_label(f'{t["key.trade.arrival"]} {t["field.required"]}', exact=True).select_option('boat')
    trade.get_by_label(t['key.trade.every_days'], exact=True).fill('7')
    trade.get_by_label(t['trade.hours_start'], exact=True).fill('02:00')
    trade.get_by_label(t['trade.hours_end'], exact=True).fill('04:00')
    expect(preview).to_contain_text('every_days=7')
    expect(preview).to_contain_text('hours=02:00-04:00')

    # stock (user 2026-11-16: no item name typed anywhere): "Ajouter des objets" opens the list of the items a trader
    # can sell (E22-T17), searched by name and filtered by category, two items ticked then added; each line shows the
    # item's name and weight, its Module.Type only as tooltip; a line replaced from the same list, a line removed
    stock_row = row_of(trade, page, t['key.trade.item'])
    stock_row.get_by_role('button', name=t['browser.add_items'], exact=True).click()
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
    expect(first.locator('.item-kg')).to_have_text('0,1 kg')
    expect(first).to_have_attribute('title', 'Base.Bandage')
    if trade.locator('.stock-line input[type=text], .stock-line input:not([type])').count():
        failures.append(f'{lang}: a stock line still has a text field')
    print(f'{lang}: "hache" -> nothing (an axe has no price); "bandage" + "Nourriture"/"whisky" ticked and added '
          f'({", ".join(found[:3])}... all sellable): 2 lines, "Bandage 0,1 kg", type in the tooltip only')
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
    accept.get_by_role('button', name=t['browser.add_items'], exact=True).click()
    dialog = page.locator('dialog.item-browser.multi')
    dialog.get_by_label(t['browser.search'], exact=True).fill('antibio')
    expect(options.first).to_have_attribute('data-type', 'Base.Antibiotics')
    options.first.click()
    dialog.locator('.browser-add').click()
    expect(preview).to_contain_text('accept=Base.Antibiotics')
    expect(accept.locator('.accept-line .item-choice').first).to_have_attribute('title', 'Base.Antibiotics')
    print(f'{lang}: accepts: {cats.count()} categories offered, "{t["category.cash"]}" ticked, Antibiotics added '
          '(accept=cash, accept=Base.Antibiotics)')
    # a lot, then the stock line taken from it
    trade.get_by_role('button', name=t['lot.add']).click()
    lot_name = trade.get_by_label(t['lot.name'].replace('{n}', '1'), exact=True)
    lot_name.fill('Graines')
    lot_name.press('Tab')
    expect(preview).to_contain_text('group=graines:1-3')
    trade.locator('.stock-line').first.get_by_label(t['stock.amount'], exact=True).select_option('graines')
    expect(preview).to_contain_text('item=Base.Bandage:graines')
    print(f'{lang}: lot "graines" made (group=graines:1-3) and chosen by the stock line')
    margin = trade.locator('.row', has=page.get_by_text(t['key.trade.margin'], exact=True))
    margin.get_by_label(t['field.min'], exact=True).fill('10')
    margin.get_by_label(t['field.max'], exact=True).fill('40')
    expect(preview).to_contain_text('margin=0.10-0.40')
    trade.evaluate("d => d.scrollIntoView({block: 'start'})")
    page.screenshot(path=str(shots / f'atelier-trade-{lang}.png'))

    note = page.locator('details.fold', has_text=t['advanced.note.enable'])
    note.locator('summary').click()
    note.get_by_label(t['advanced.note.enable']).check()
    line = note.get_by_label(t['note.line'].replace('{n}', '1'), exact=True)
    line.fill('Mae écoute sur %1 MHz')
    counter = note.locator('.note-line .counter').first
    expect(counter).to_have_text(t['note.bytes'].replace('{n}', '22').replace('{max}', '40'))
    note.get_by_role('button', name=t['note.add_line']).click()
    long_line = note.get_by_label(t['note.line'].replace('{n}', '2'), exact=True)
    long_line.fill('Une ligne bien trop longue pour tenir sur la note')
    expect(note.locator('.note-line .counter').nth(1)).to_have_class(re.compile(r'\bover\b'))
    long_line.fill('Passe le soir')
    expect(preview).to_contain_text('text=Mae écoute sur %1 MHz')
    note.get_by_role('switch').check()
    expect(preview).to_contain_text('corpse=yes')
    if note.get_by_text(t['section.advanced'], exact=True).count():
        failures.append(f'{lang}: the note of a new voice shows the advanced item and key')
    loot = note.locator('.row').filter(has=page.get_by_text(t['key.note.loot'], exact=True))
    loot.get_by_role('button', name=t['stock.add_list']).click()
    loot.get_by_label(t['stock.list'].replace('{n}', '1'), exact=True).fill('KitchenDryFood')
    loot.locator('button[data-chance="often"]').click()
    expect(preview).to_contain_text('loot=KitchenDryFood:4')
    if note.locator('datalist option').count() < 500:
        failures.append(f'{lang}: the loot list field does not offer the lists of the game')
    print(f'{lang}: note text with its count (22 / 40, too long line flagged), corpse=yes, loot=KitchenDryFood:4')
    note.evaluate("d => d.scrollIntoView({block: 'start'})")
    page.screenshot(path=str(shots / f'atelier-note-{lang}.png'))
    page.locator('#save').click()
    expect(page.locator('.toast').last).to_contain_text(t['code.voice_saved'])
    text = path.read_text(encoding='utf-8')
    verdict = game_reads(text, voice_id)
    print(f'{lang}: voice with trade and note saved, game reader: {verdict[0]} '
          f'{verdict[1] if verdict[0] != "OK" else ""}'.rstrip())
    if verdict[0] != 'OK':
        failures.append(f'{lang}: game reader refused the trade and note: {verdict[1]}\n{text}')
    # a shipped voice: its note's own item and text key stay in the advanced settings, its lots and stock shown
    page.locator('.voice', has_text='Boone Tackett').first.click()
    page.locator('.pill').nth(4).click()
    note = page.locator('details.fold', has_text=t['advanced.note.enable'])
    note.locator(':scope > summary').click()
    expect(note.get_by_text(t['note.own_item'], exact=True)).to_be_visible()
    advanced = note.locator('details.fold', has_text=t['section.advanced'])
    advanced.locator(':scope > summary').click()
    expect(advanced.locator('.item-choice')).to_have_attribute('title', re.compile(r'^RadioSurvivor\.Note'))
    trade = page.locator('details.fold', has_text=t['advanced.trade.enable'])
    trade.locator('summary').click()
    expect(trade.get_by_label(t['lot.name'].replace('{n}', '1'), exact=True)).to_have_value('alcohol')
    expect(trade.locator('.stock-line').first.locator('.item-kg')).not_to_have_text('')
    expect(page.locator('.dirty')).to_have_text(t['editor.saved'])
    print(f'{lang}: shipped voice: note item and key in "{t["section.advanced"]}", lot "alcohol" and weights shown, '
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
    """Reloads the page, leaving an unsaved voice if one is open (the page asks before leaving it)."""
    def accept(dialog):
        dialog.accept()
    page.on('dialog', accept)
    try:
        page.reload()
    finally:
        page.remove_listener('dialog', accept)


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
    """Every stock line of the shipped voice on the same grid: the item, quantity mode and "from ... to ..." cells of a
    line taken from a lot (empty range cell) and of a line with a number share their x and width."""
    lines = trade.locator('.stock-line')
    lot_line = lines.filter(has=page.locator('.cell-empty')).first
    number_line = lines.filter(has=page.locator('.range')).first
    cells = {name: (boxes(lot_line.locator(f':scope > {sel}')), boxes(number_line.locator(f':scope > {sel}')))
             for name, sel in (('item', '.item-choice'), ('mode', 'select'), ('range', ':nth-child(3)'))}
    print(f'{lang}: stock grid at {width} px, (x, width) lot line / number line: '
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
    page.get_by_role('button', name=t['editor.preview_hide'], exact=True).click()   # the form alone, full width
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
    stock_row.get_by_role('button', name=t['browser.add_items'], exact=True).click()
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
    expect(first.locator('.b-kg')).to_have_text('1,7 kg')
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
    stock_row.get_by_role('button', name=t['browser.add_items'], exact=True).click()
    for word in ('chili', 'riz'):
        search.fill(word)
        dialog.locator('[role=option]').first.click()
    dialog.locator('.browser-add').click()
    expect(dialog).to_have_count(0)
    added = trade.locator('.stock-line').count() - before
    page.get_by_role('button', name=t['editor.preview'], exact=True).click()
    preview = page.locator('.sheet-preview')
    expect(preview).to_contain_text('item=Base.CannedChili:1')
    expect(preview).to_contain_text('item=Base.Rice:1')
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


def check_surveys(page, t: dict, lang: str, voice_id: str, name: str, working: Path, survey_file: Path, shots: Path,
                  failures: list[str]) -> None:
    """E22-T08: the places recorded in game listed under the voice's places, one added to the voice."""
    page.set_viewport_size({'width': 1280, 'height': 900})
    page.locator('.voice', has_text=name).first.click()
    page.locator('.pill').nth(3).click()
    page.locator('details.fold').first.evaluate('d => d.open = true')
    items = page.locator('li.survey')
    expect(items).to_have_count(2)
    expect(items.first).to_contain_text('10612, 9307, 0')                  # newest first: the dumpster
    expect(items.nth(1)).to_contain_text('Kitchen')
    places_before = page.locator('details.fold').first.locator('.card').count()
    items.first.get_by_role('button', name=t['surveys.add']).click()
    ask = page.locator('.surveys-block .notice')
    label = ask.get_by_label(t['places.label'], exact=True)
    expect(label).to_have_value('Bin')
    label.fill("Benne de l'église")
    ask.get_by_role('button', name=t['places.add_ok']).click()
    cards = page.locator('details.fold').first.locator('.card')
    expect(cards).to_have_count(places_before + 1)
    card = cards.last
    expect(card.get_by_label(t['places.label'], exact=True)).to_have_value("Benne de l'église")
    for axis, value in zip(('x', 'y', 'z'), ('10612', '9307', '0')):
        expect(card.get_by_label(axis, exact=True)).to_have_value(value)
    expect(card.locator('.check', has_text=t['use.drop']).locator('input')).to_be_checked()
    expect(card.locator('.check', has_text=t['use.mark']).locator('input')).not_to_be_checked()
    expect(page.locator('li.survey').first).to_contain_text(t['surveys.known'])
    page.locator('li.survey').first.scroll_into_view_if_needed()
    page.screenshot(path=str(shots / f'atelier-surveys-{lang}.png'), full_page=True)
    page.locator('#save').click()
    expect(page.locator('.toast')).to_contain_text(t['code.voice_saved'])
    text = (working / f'{voice_id}.txt').read_text(encoding='utf-8')
    verdict = game_reads(text, voice_id)
    placed = re.search(r"\[place [a-z0-9_]+\]\nat=10612,9307,0\nlabel=Benne de l'église\nuse=drop\n", text)
    print(f'{lang}: places recorded in game: 2 listed newest first, "{t["surveys.add"]}" made a dead drop at '
          f'10612,9307,0: {bool(placed)}, game reader: {verdict[0]}')
    if not placed:
        failures.append(f'{lang}: place from the survey missing in the sheet\n{text}')
    if verdict[0] != 'OK':
        failures.append(f'{lang}: game reader refused the place from the survey: {verdict[1]}')
    if survey_file.read_text(encoding='utf-8') != SURVEYS:
        failures.append(f'{lang}: the survey file was changed by the workshop')


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
                                       'OPENAI_KEY': 'fake'})
        try:
            with sync_playwright() as pw:
                browser = pw.chromium.launch()
                for locale, lang in LOCALES:
                    t = strings(lang)
                    voice_id, name = f'smoke_{lang}', f'Smoke Tester {lang.upper()}'
                    context = browser.new_context(locale=locale, viewport={'width': 1280, 'height': 900})
                    page = context.new_page()
                    errors: list[str] = []
                    page.on('console', lambda m, errors=errors: errors.append(m.text) if m.type == 'error' else None)
                    page.on('pageerror', lambda e, errors=errors: errors.append(str(e)))
                    live.ai = ai if lang == 'fr' else None
                    page.goto(server.url)
                    expect(page.locator('h1')).to_have_text(t['app.title'])
                    create_voice(page, t, voice_id, name)
                    path = working / f'{voice_id}.txt'
                    text = path.read_text(encoding='utf-8') if path.is_file() else ''
                    verdict = game_reads(text, voice_id) if text else ('MISSING', '')
                    print(f'{lang}: {path.name} {"written" if text else "missing"}, game reader: {verdict[0]} '
                          f'{verdict[1] if verdict[0] != "OK" else ""}'.rstrip())
                    if verdict[0] != 'OK':
                        failures.append(f'{lang}: game reader refused the sheet: {verdict[1]}\n{text}')
                    exported = page.request.get(server.url.rstrip('/') + page.locator('a[download]').get_attribute('href'))
                    if exported.text() != text:
                        failures.append(f'{lang}: export differs from the saved file')
                    page.locator('input[type=file]').set_input_files(files=[{
                        'name': f'{voice_id}.txt', 'mimeType': 'text/plain', 'buffer': text.encode('utf-8')}])
                    page.locator('.notice').get_by_label(t['who.id'], exact=True).fill(f'{voice_id}_copy')
                    page.locator('.notice').get_by_role('button', name=t['import.ok']).click()
                    expect(page.locator('.toast')).to_contain_text(t['code.voice_imported'])
                    copy = working / f'{voice_id}_copy.txt'
                    imported = copy.is_file() and copy.read_text(encoding='utf-8') == text.replace(
                        f'id={voice_id}\n', f'id={voice_id}_copy\n')
                    print(f'{lang}: export identical: {exported.text() == text}, import under a new id: {imported}')
                    if not imported:
                        failures.append(f'{lang}: import with a new id failed')
                    page.locator('.voice', has_text=name).first.click()   # the original, before its copy
                    page.locator('.pill').nth(3).click()                    # missions step for the screenshot
                    page.locator('details.fold').first.evaluate('d => d.open = true')
                    page.screenshot(path=str(shots / f'atelier-{lang}.png'), full_page=True)
                    if lang == 'fr':
                        check_help(page, t, lang, shots, failures)
                    page.set_viewport_size({'width': 800, 'height': 900})
                    width = page.evaluate('document.documentElement.scrollWidth')
                    print(f'{lang}: page width at 800 px viewport = {width}')
                    if width > 800:
                        failures.append(f'{lang}: horizontal scroll at 800 px ({width} px)')
                    check_live(page, t, lang, voice_id, name, text, console, running, shots, failures)
                    check_ai(page, t, lang, path, shots, failures)
                    if lang == 'fr':
                        check_stock(page, t, lang, path, voice_id, shots, failures)
                        check_item_browser(page, t, lang, name, shots, failures)
                        check_surveys(page, t, lang, voice_id, name, working, survey_file, shots, failures)
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
