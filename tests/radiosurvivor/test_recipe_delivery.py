"""Recipe search kept by the server, delivery, notebook entry and teaching (E27-T04, ADR recettes-radio D04 to D07,
D09, D10), on the benches.

    python RadioSurvivor/tests/radiosurvivor/test_recipe_delivery.py

- SearchTests (mimetic bench, tests/commun/harness.py): RS_RecipeSearches keeps ONE search per notebook character and
  per voice in the private state of the voices (RS_State), ready at the game hour of the voice's delay
  (GameTime.getWorldAgeHours), replaced by a new one, cleared once delivered, forgotten at death; field recipe= of the
  requests as the bridge reads it (npc_protocol.decode).
- DeliveryTests: RS_RecipeDelivery: a "recipe" line in the Radio history of the notebook (id, voice frequency, game
  date, learned flag); IsoGameCharacter.learnRecipe then sendSyncPlayerFields(player, PF_Recipes = 1) (vanilla
  ISResearchRecipe.lua:83-85) only at reputation "good", for a recipe that must be learned (CraftRecipe.needToBeLearn)
  of a job of the voice; ScriptManager.getCraftRecipe nil -> ignored with a log line.
- RecipeNoteTests: client view (RS_RecipeNote): the recipe read from the game in the player's language
  (RS_RecipeCatalog.describe), learned or to learn; unknown recipe: its id in words.
- ServerFlowTests (bench machine of tests/commun/bench_game.py + notebook simulation of tests/coreai/test_carnet.py):
  the real RadioSurvivor_Server: "searched" of radio_reply stored, recipe= sent with ready no / yes from the game
  time, "recipes" delivered and the notebook Radio tab shows the entry.
Doubles only: they do not prove the Java API (in-game check of the plan).
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
sys.path.insert(0, str(bench_paths.ROOT / 'bridge'))
import npc_protocol as npc  # noqa: E402
from harness import Harness  # noqa: E402
from bench_game import lua_list  # noqa: E402
from test_radio_history import SERVER_SETUP, CLIENT_SETUP  # noqa: E402
from test_recipe_index import DOUBLES  # noqa: E402

# Server doubles: CraftRecipe (CraftRecipe.java getName 146, getCategory 228, needToBeLearn 185), ScriptManager.
# getCraftRecipe (ScriptManager.java:975, null when unknown), IsoGameCharacter.learnRecipe (IsoGameCharacter.java:
# 10752-10765: false when already known), the global sendSyncPlayerFields (LuaManager.java:3730, no-op off a server).
GAME = r'''
local H = HARNESS
CRAFTS = {}
function craft(id, category, learn)
    CRAFTS[id] = H.fake('CraftRecipe', {
        getName = function() return id end,
        getCategory = function() return category end,
        needToBeLearn = function() return learn == true end,
    })
end
SCRIPTS = H.fake('ScriptManager', { getCraftRecipe = function(_, name) return CRAFTS[name] end })
getScriptManager = function() return SCRIPTS end
SYNCED = {}
sendSyncPlayerFields = function(player, params) SYNCED[#SYNCED + 1] = player:getUsername() .. ':' .. tostring(params) end
local p = HARNESS.players.A
p.knownList = {}
-- Method of the IsoPlayer instance of the harness: checked against IsoGameCharacter.learnRecipe(String) when set.
p.learnRecipe = function(self, name)
    if self.knownList[name] then return false end
    self.knownList[name] = true
    return true
end
Searches = require 'RadioSurvivor/RS_RecipeSearches'
Delivery = require 'RadioSurvivor/RS_RecipeDelivery'
Help = require 'RadioSurvivor/RS_RecipeHelp'
MARTHA = { id = 'martha', help = { jobs = { 'tailoring', 'cooking' }, from = 'neutral', delay = 'hour' } }
function hours(h) HARNESS.clock.ageHours = h end
'''


def decoded(hex_text: str) -> dict:
    value = npc.decode(bytes.fromhex(hex_text))
    out = dict(value)
    for key in ('ids', 'keywords'):
        if key in out:
            out[key] = [out[key][i] for i in range(1, len(out[key]) + 1)]
    return out


class Bench(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp', clients=('A',))
        self.h.server.g.NEW_WORLD = True
        self.h.load('server', SERVER_SETUP)
        self.h.load('A', CLIENT_SETUP)
        self.h.load('server', "bind('A', 'char-a')")
        self.h.load('server', GAME)
        self.h.load('server', "hours(10)")

    def tearDown(self):
        self.h.close()

    def server(self, code):
        return self.h.load('server', code)

    def eval(self, expr):
        return self.h.eval('server', expr)


class SearchTests(Bench):
    def store(self, ids=('MakeSheetRope',), keywords=('sheet rope',), delay='hour', voice='martha'):
        ids_lua = ', '.join(f"'{i}'" for i in ids)
        kw_lua = ', '.join(f"'{k}'" for k in keywords)
        return self.eval(f"Searches.store('char-a', '{voice}', '{delay}', {{ ids = {{ {ids_lua} }}, "
                         f"keywords = {{ {kw_lua} }} }})")

    def field(self, voice='martha'):
        self.server(f"F, READY = Searches.field('char-a', '{voice}')")
        return self.h.server.g.F, self.h.server.g.READY

    def test_stored_with_ready_at_from_the_delay_table(self):
        self.assertTrue(self.store())
        self.assertEqual(self.eval("Searches.pending('char-a', 'martha').readyAt"), 11)
        self.assertEqual(lua_list(self.eval("Searches.pending('char-a', 'martha').ids")), ['MakeSheetRope'])
        self.assertTrue(self.eval("require('RadioSurvivor/RS_State').dirty"))
        self.assertEqual(dict(self.eval('Searches.DELAY_HOURS')), {'now': 0, 'hour': 1, 'half_day': 12, 'day': 24})

    def test_too_early_not_ready_then_ready_on_time_without_expiry(self):
        self.store(delay='half_day')
        hex_text, ready = self.field()
        self.assertFalse(ready)
        self.assertEqual(decoded(hex_text), {'ids': ['MakeSheetRope'], 'ready': False, 'keywords': ['sheet rope']})
        self.server('hours(21.5)')
        self.assertFalse(self.field()[1])
        self.server('hours(22)')
        hex_text, ready = self.field()
        self.assertTrue(ready)
        self.assertTrue(decoded(hex_text)['ready'])
        self.server('hours(500)')
        self.assertTrue(self.field()[1], 'no expiry (D07)')

    def test_one_search_per_voice_a_new_one_replaces_the_old(self):
        self.store()
        self.store(ids=('CookPotOfSoup',), keywords=('soup',), delay='day')
        self.assertEqual(lua_list(self.eval("Searches.pending('char-a', 'martha').ids")), ['CookPotOfSoup'])
        self.assertEqual(self.eval("Searches.pending('char-a', 'martha').readyAt"), 34)
        self.store(ids=(), keywords=('airplane',), voice='other')
        self.assertEqual(decoded(self.field('other')[0])['ids'], [])
        self.assertEqual(lua_list(self.eval("Searches.pending('char-a', 'martha').ids")), ['CookPotOfSoup'])

    def test_cleared_and_forgotten(self):
        self.store()
        self.server("Searches.clear('char-a', 'martha')")
        self.assertIsNone(self.field()[0])
        self.store()
        self.server("Searches.forget('char-a')")
        self.assertIsNone(self.eval("Searches.pending('char-a', 'martha')"))

    def test_bad_searches_are_refused(self):
        for bad in ("{ ids = 'x' }", "{ ids = { 3 } }", "nil"):
            self.assertFalse(self.eval(f"Searches.store('char-a', 'martha', 'hour', {bad})"), bad)
        self.assertFalse(self.eval("Searches.store(nil, 'martha', 'hour', { ids = {} })"))
        self.assertIsNone(self.eval("Searches.pending('char-a', 'martha')"))


class DeliveryTests(Bench):
    def deliver(self, ids, level, khz=146000):
        ids_lua = ', '.join(f"'{i}'" for i in ids)
        lvl = f"'{level}'" if level else 'nil'
        return self.server(f"Delivery.deliver({{ cid = 'char-a', khz = {khz}, sheet = MARTHA, "
                           f"player = HARNESS.players.A, level = {lvl} }}, {{ {ids_lua} }})")

    def lines(self):
        radio = self.eval("require('CoreAI/CA_History').radio('char-a')")
        if radio is None:
            return []
        return [(l.kind, l.text) for f in lua_list(radio.frequencies) for l in lua_list(f.lines)]

    def known(self):
        return sorted(k for k, v in dict(self.eval('HARNESS.players.A.knownList')).items() if v)

    def test_good_reputation_teaches_a_recipe_of_the_voice_jobs(self):
        self.server("craft('MakeSheetRope', 'Tailoring', true)")
        self.deliver(['MakeSheetRope'], 'good')
        self.assertEqual(self.known(), ['MakeSheetRope'])
        self.assertEqual(lua_list(self.h.server.g.SYNCED), ['A:1'])
        self.assertEqual(self.lines(), [('recipe', 'MakeSheetRope|1')])

    def test_neutral_reputation_never_teaches(self):
        self.server("craft('MakeSheetRope', 'Tailoring', true)")
        self.deliver(['MakeSheetRope'], 'neutral')
        self.deliver(['MakeSheetRope'], None)
        self.assertEqual(self.known(), [])
        self.assertEqual(lua_list(self.h.server.g.SYNCED), [])
        self.assertEqual(self.lines(), [('recipe', 'MakeSheetRope|0'), ('recipe', 'MakeSheetRope|0')])

    def test_recipe_outside_the_voice_jobs_is_never_taught(self):
        self.server("craft('MakeMetalSheet', 'Metalworking', true)")
        self.deliver(['MakeMetalSheet'], 'good')
        self.assertEqual(self.known(), [])
        self.assertEqual(self.lines(), [('recipe', 'MakeMetalSheet|0')])

    def test_recipe_without_learning_is_never_learned(self):
        self.server("craft('CookPotOfSoup', 'Cooking', false)")
        self.deliver(['CookPotOfSoup'], 'good')
        self.assertEqual(self.known(), [])
        self.assertEqual(self.lines(), [('recipe', 'CookPotOfSoup|0')])

    def test_already_known_recipe_is_not_marked_learned(self):
        self.server("craft('MakeSheetRope', 'Tailoring', true); HARNESS.players.A.knownList.MakeSheetRope = true")
        self.deliver(['MakeSheetRope'], 'good')
        self.assertEqual(lua_list(self.h.server.g.SYNCED), [])
        self.assertEqual(self.lines(), [('recipe', 'MakeSheetRope|0')])

    def test_unknown_recipe_is_ignored_with_a_log_line(self):
        self.server("craft('CookPotOfSoup', 'Cooking', false)")
        self.deliver(['NoSuchRecipe', 'CookPotOfSoup'], 'good')
        self.assertEqual(self.lines(), [('recipe', 'CookPotOfSoup|0')])
        self.assertTrue(any("recipe 'NoSuchRecipe' unknown" in line for line in self.h.logs('server')),
                        self.h.logs('server'))

    def test_no_character_no_entry(self):
        self.server("craft('MakeSheetRope', 'Tailoring', true)")
        self.server("Delivery.deliver({ khz = 146000, sheet = MARTHA, player = HARNESS.players.A, level = 'good' }, "
                    "{ 'MakeSheetRope' })")
        self.assertEqual((self.known(), self.lines()), ([], []))

    def test_answered_stores_clears_and_delivers(self):
        self.server("craft('MakeSheetRope', 'Tailoring', true)")
        self.server("REQ = { cid = 'char-a', voice = 'martha', khz = 146000 }; "
                    "CTX = { sheet = MARTHA, player = HARNESS.players.A, level = 'good' }")
        self.server("Help.answered(REQ, { searched = { ids = { 'MakeSheetRope' }, keywords = { 'sheet rope' } } }, CTX)")
        self.assertEqual(self.eval("Searches.pending('char-a', 'martha').readyAt"), 11)
        self.server("Help.request(REQ)")
        self.assertFalse(self.h.server.g.REQ.recipeReady)
        self.assertFalse(decoded(self.h.server.g.REQ.recipe)['ready'])
        self.server("hours(11); Help.request(REQ)")
        self.assertTrue(self.h.server.g.REQ.recipeReady)
        self.server("Help.answered(REQ, { recipes = { 'MakeSheetRope' } }, CTX)")
        self.assertIsNone(self.eval("Searches.pending('char-a', 'martha')"))
        self.assertEqual(self.lines(), [('recipe', 'MakeSheetRope|1')])
        self.server("Help.request(REQ)")
        self.assertIsNone(self.h.server.g.REQ.recipe)

    def test_answer_without_delivery_keeps_the_search(self):
        self.server("REQ = { cid = 'char-a', voice = 'martha', khz = 146000 }; CTX = { sheet = MARTHA }")
        self.server("Help.answered(REQ, { searched = { ids = {}, keywords = { 'airplane' } } }, CTX)")
        self.server("hours(11); Help.request(REQ); Help.answered(REQ, {}, CTX)")
        self.assertIsNotNone(self.eval("Searches.pending('char-a', 'martha')"))


# Client: the recipes of the game in the player's language (names given by the game: here French).
CLIENT_RECIPES = r'''
local H = HARNESS
local sheet = item('Base.RippedSheets', 'Draps dechires')
local denim = item('Base.DenimStrips', 'Bandes de jean')
local needle = item('Base.Needle', 'Aiguille')
local rope = item('Base.SheetRope', 'Corde en draps')
local water = fluid('Water', 'Eau')
RECIPES = {
    recipe({ id = 'MakeSheetRope', tname = 'Corde en draps', category = 'Tailoring', learn = true,
        inputs = { input({ sheet, denim }, { count = 2 }), input({ needle }, { keep = true }),
                   input({}, { res = RT.Fluid, fluids = { water }, amount = 0.5 }) },
        outputs = { output({ rope }) }, skills = { skill('Tailoring', 2) } }),
}
SCRIPTS = H.fake('ScriptManager', { getCraftRecipe = function(_, name)
    for _, r in ipairs(RECIPES) do if r:getName() == name then return r end end
    return nil end })
getScriptManager = function() return SCRIPTS end
local tailoring = { name = 'Couture' }
Perks = { MAX = { name = 'MAX' }, FromString = function(id) if id == 'Tailoring' then return tailoring end
    return Perks.MAX end }
PerkFactory = { getPerkName = function(perk) return perk.name end }
Note = require 'RadioSurvivor/RS_RecipeNote'
'''


class RecipeNoteTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp', clients=('A',))
        self.h.load('A', CLIENT_SETUP)
        self.h.load('A', DOUBLES)
        self.h.load('A', "LANG = FR")
        self.h.load('A', CLIENT_RECIPES)

    def tearDown(self):
        self.h.close()

    def text(self, line):
        return self.h.eval('A', f"Note.text('{line}')")

    def test_recipe_read_from_the_game_in_the_player_language(self):
        text = self.text('MakeSheetRope|0')
        for part in ('Corde en draps', 'IGUI_RS_RecipeMakes|1 x Corde en draps',
                     'IGUI_RS_RecipeNeeds|2 x Draps dechires IGUI_RS_RecipeOr Bandes de jean, IGUI_RS_RecipeLitres|0.5|Eau',
                     'IGUI_RS_RecipeTools|Aiguille', 'IGUI_RS_RecipeSkill|Couture|2', 'IGUI_RS_RecipeMustLearn'):
            self.assertIn(part, text)
        self.assertNotIn('IGUI_RS_RecipeLearned', text)

    def test_learned_recipe_says_so(self):
        text = self.text('MakeSheetRope|1')
        self.assertIn('IGUI_RS_RecipeLearned', text)
        self.assertNotIn('IGUI_RS_RecipeMustLearn', text)

    def test_unknown_recipe_shows_its_id_in_words(self):
        self.assertEqual(self.text('MakeTinFoilHat|0'), 'Make Tin Foil Hat')


HELPER_SHEET = """format=1
id=martha
name=Martha Stitch
frequency=146.0
[help]
jobs=tailoring
delay=hour
[prompt]
You are Martha Stitch, a seamstress.
"""


class ServerFlowTests(unittest.TestCase):
    """Real RadioSurvivor_Server and notebook server (tests/coreai/test_carnet.py Simulation), Martha on 146.0."""

    def setUp(self):
        from test_carnet import Simulation, NOTEBOOK_UI
        self.notebook_ui = NOTEBOOK_UI
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_recipe_delivery_'))
        sim = Simulation(self.tmp / 'mp')
        (sim.path / 'personas').mkdir(parents=True, exist_ok=True)
        (sim.path / 'personas' / 'martha.txt').write_text(HELPER_SHEET, encoding='utf-8')
        sim.server.g.WORLD_AGE_HOURS = 100
        sim.server.rt.execute(
            "CRAFTS = { MakeSheetRope = { getName = function() return 'MakeSheetRope' end, "
            "getCategory = function() return 'Tailoring' end, needToBeLearn = function() return true end } }; "
            "getScriptManager = function() return { getCraftRecipe = function(_, n) return CRAFTS[n] end } end; "
            "SYNCED = {}; sendSyncPlayerFields = function(p, f) SYNCED[#SYNCED + 1] = f end")
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        self.sim = sim
        c = sim.add_client('alice')
        c.rt.execute("getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do "
                     "t[#t + 1] = tostring(select(i, ...)) end return table.concat(t, '|') end")
        c.rt.execute("Talk = require('RadioSurvivor/RS_RadioTalk'); History = Talk.History; "
                     "local Const = require('RadioSurvivor/RadioSurvivor_Const'); "
                     "Events.OnServerCommand.Add(function(m, cmd, a) if m == Const.MODULE then Talk.handle(cmd, a or {}) end end); "
                     ""
                     "function texts(khz) local out = {} for _, l in ipairs(History.lines(khz)) do "
                     "out[#out + 1] = l.kind .. ':' .. l.text end return out end; "
                     "getScriptManager = function() return { getCraftRecipe = function() return nil end } end")
        c.rt.execute('getPlayer().radio.device.channel = 146000')
        sim.server.g.PLAYERS['alice'].radio.device.channel = 146000
        self.alice = c

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def say(self, text):
        self.sim.clock.offset += 11000
        self.alice.rt.execute('Talk.resetForTests()')
        self.assertTrue(self.alice.rt.eval(f"Talk.send(getPlayer(), getPlayer().radio, '{text}')"))
        lines = (self.sim.path / 'requests.txt').read_text(encoding='utf-8').splitlines()
        start = max(i for i, l in enumerate(lines) if l.startswith('req='))
        block = {}
        for line in lines[start + 1:]:
            if line.startswith('req=') or '=' not in line:
                break
            key, value = line.split('=', 1)
            block[key] = value
        block['id'] = lines[start][4:]
        return block

    def respond(self, req, body):
        if isinstance(body, str):
            text = f'resp={req["id"]}\nline={body}\nend\n'
        else:
            value = dict({'version': 2, 'kind': 'radio_reply', 'id': req['id'], 'actions': []}, **body)
            text = f'resp={req["id"]}\npayload={npc.encode(value).hex()}\nend\n'
        (self.sim.path / 'responses.txt').write_text(text, encoding='utf-8')
        self.sim.clock.offset += 1000
        self.sim.server.g.fire('OnTick')
        self.sim.server.g.finishAiring()

    def test_search_kept_too_early_then_answered_and_noted(self):
        req = self.say('How do I make a rope?')
        self.assertEqual(req.get('voice'), 'martha')
        self.assertNotIn('recipe', req)
        self.respond(req, {'say': ['Let me look, call back in an hour.'],
                           'searched': {'ids': ['MakeSheetRope'], 'keywords': ['sheet rope']}})
        req = self.say('So?')
        self.assertEqual(decoded(req['recipe']), {'ids': ['MakeSheetRope'], 'ready': False, 'keywords': ['sheet rope']})
        self.respond(req, 'Not yet, call back later.')
        self.sim.server.g.WORLD_AGE_HOURS = 101
        req = self.say('So?')
        self.assertTrue(decoded(req['recipe'])['ready'])
        self.respond(req, {'say': ['Two sheets and a needle.'], 'recipes': ['MakeSheetRope']})
        self.assertIn('recipe:MakeSheetRope|0', lua_list(self.alice.rt.eval('texts(146000)')))
        self.assertEqual(lua_list(self.sim.server.g.SYNCED), [], 'neutral: nothing taught')
        req = self.say('Thanks!')
        self.assertNotIn('recipe', req)
        # The Radio tab of the notebook shows the entry (RS_NotebookRadio, kind "recipe").
        self.alice.rt.execute(self.notebook_ui)
        self.alice.load_notebook()
        self.alice.g.CoreAI.notebook.toggle()
        window = self.alice.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Radio')
        self.assertRegex(window.detail.text, r'<RGB:0\.70,0\.18,0\.08> IGUI_RS_Radio_recipe\|[^|]+\|Make Sheet Rope')


if __name__ == '__main__':
    unittest.main()
