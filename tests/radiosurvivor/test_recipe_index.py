"""Recipe index exported by the authority (E27-T01, ADR recettes-radio D02, D08, D11), on the mimetic bench.

    python RadioSurvivor/tests/radiosurvivor/test_recipe_index.py

At the start of the authority (OnGameStart in solo, OnServerStarted on a dedicated server), RS_RecipeIndex asks the
game for every craft recipe it loaded (RS_RecipeCatalog over ScriptManager.getAllCraftRecipes) and writes
Zomboid/Lua/batman_CoreAI/recipes.json for the bridge. Java doubles follow the 42.22 sources: ArrayList indices from 0,
nil where Java returns null (Item.getLearnedRecipes), strict classes checked against the exposed API.
"""
import json
import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from harness import Harness

# Game doubles: items, input/output lines, recipes, skills, ScriptManager, Translator (static), Language.
DOUBLES = r"""
local H = HARNESS
RT = { Item = H.fake('ResourceType', {}), Fluid = H.fake('ResourceType', {}), Energy = H.fake('ResourceType', {}) }
ResourceType = RT
local LanguageDouble = H.class('LanguageDouble')
LanguageDouble.__tostring = function(o) return o.code end
EN = setmetatable({ code = 'EN' }, LanguageDouble)
FR = setmetatable({ code = 'FR' }, LanguageDouble)
LANG = EN
Translator = H.fake('Translator', {
    getLanguage = function() return LANG end,
    getDefaultLanguage = function() return EN end,
})
function item(full, display, learned)
    return H.fake('Item', {
        getFullName = function() return full end,
        getDisplayName = function() return display or full end,
        getLearnedRecipes = function() if learned then return H.list(learned) end return nil end,
    })
end
function fluid(id, display)
    return H.fake('Fluid', {
        getFluidTypeString = function() return id end,
        getDisplayName = function() return display or 'Fluid' end,
    })
end
-- InputScript: o.res (RT.Item by default), o.fluids (getPossibleInputFluids), o.amount (float, getAmount),
-- o.consume (nested '-' line: getConsumeFromItemScript), o.create (nested '+' line: getCreateToItemScript); nil = null.
function input(items, o)
    o = o or {}
    return H.fake('InputScript', {
        getResourceType = function() return o.res or RT.Item end,
        isAutomationOnly = function() return o.auto == true end,
        isAcceptsAnyItem = function() return o.any == true end,
        isAcceptsAnyFluid = function() return o.anyFluid == true end,
        isKeep = function() return o.keep == true end,
        isTool = function() return o.tool == true end,
        getIntAmount = function() return o.count or 1 end,
        getAmount = function() return o.amount or 1.0 end,
        getPossibleInputItems = function() return H.list(items) end,
        getPossibleInputFluids = function() return H.list(o.fluids or {}) end,
        getConsumeFromItemScript = function() return o.consume end,
        getCreateToItemScript = function() return o.create end,
    })
end
function output(items, o)
    o = o or {}
    return H.fake('OutputScript', {
        getResourceType = function() return o.res or RT.Item end,
        isAutomationOnly = function() return o.auto == true end,
        getIntAmount = function() return o.count or 1 end,
        getAmount = function() return o.amount or 1.0 end,
        getPossibleResultItems = function() return H.list(items) end,
        getPossibleResultFluids = function() return H.list(o.fluids or {}) end,
        getCreateToItemScript = function() return o.create end,
    })
end
function skill(perk, level)
    local p = H.fake('Perk', { getId = function() return perk end })
    return H.fake('RequiredSkill', { getPerk = function() return p end, getLevel = function() return level end })
end
function recipe(o)
    local skills = o.skills or {}
    return H.fake('CraftRecipe', {
        getName = function() return o.id end,
        getTranslationName = function() return o.tname or o.id end,
        getCategory = function() return o.category or 'Miscellaneous' end,
        getTags = function() return H.list(o.tags or {}) end,
        getInputs = function() return H.list(o.inputs or {}) end,
        getOutputs = function() return H.list(o.outputs or {}) end,
        needToBeLearn = function() return o.learn == true end,
        isVanilla = function() return o.mod == nil end,
        getModID = function() return o.mod or 'pz-vanilla' end,
        getRequiredSkillCount = function() return #skills end,
        getRequiredSkill = function(self, i)
            local s = skills[i + 1]
            if s == nil then error('IndexOutOfBoundsException: Index ' .. i) end
            return s
        end,
    })
end
RECIPES, ITEMS = {}, {}
ScriptManager = { instance = H.fake('ScriptManager', {
    getAllCraftRecipes = function() return H.list(RECIPES) end,
    getAllItems = function() return H.list(ITEMS) end,
}) }
"""

# A small world: a vanilla tailoring recipe, a mod recipe of an unknown category, a recipe taught by a magazine,
# a right-click-only recipe, fluid and "any item" input lines.
WORLD = r"""
local sheet = item('Base.RippedSheets', 'Ripped Sheets')
local needle = item('Base.Needle', 'Needle')
local rope = item('Base.SheetRope', 'Sheet Rope')
local mag = item('Base.MetalworkMag1', 'Metalwork Magazine Vol. 1', { 'MakeMetalSheet' })
local book = item('Base.BookMetalWelding1', 'Metalworking for Beginners', { 'MakeMetalSheet' })
local scrap = item('Base.ScrapMetal', 'Scrap Metal')
local metal = item('Base.SheetMetal', 'Metal Sheet')
local brick = item('MyMod.WeirdBrick', 'Weird Brick')
local suture = item('Base.SutureNeedle', 'Suture Needle')
local pot = item('Base.Pot', 'Cooking Pot')
local bucket = item('Base.Bucket', 'Bucket')
local flour = item('Base.Flour2', 'Flour')
local dough = item('Base.Dough', 'Dough')
local water = fluid('Water', 'Water')
local tainted = fluid('TaintedWater', 'Tainted Water')
local dye = fluid('Dye', 'Dye')
ITEMS = { sheet, needle, rope, mag, book, scrap, metal, brick, suture, pot, bucket, flour, dough }
RECIPES = {
    recipe({ id = 'MakeSheetRope', tname = 'Make Sheet Rope', category = 'Tailoring',
        inputs = { input({ sheet }, { count = 2 }), input({ needle, suture }, { keep = true }),
                   input({}, { res = RT.Fluid, fluids = { water, tainted }, amount = 0.30000001192092896 }),
                   input({ sheet, needle }, { any = true }), input({}, { res = RT.Energy }),
                   input({ rope }, { auto = true }), input({}, { res = RT.Fluid, anyFluid = true }) },
        outputs = { output({ rope }), output({}, { res = RT.Energy }), output({ sheet }, { auto = true }),
                    output({}, { res = RT.Fluid, fluids = { dye }, amount = 0.5 }) },
        skills = { skill('Tailoring', 2) } }),
    recipe({ id = 'MakeDough', tname = 'Make Dough', category = 'Cooking',
        inputs = {
            input({ pot }, { keep = true, consume = input({}, { res = RT.Fluid, fluids = { water }, amount = 1.0 }) }),
            input({ bucket }, { keep = true, create = output({}, { res = RT.Fluid, fluids = { dye }, amount = 2.0 }) }),
            input({ flour }, { any = true, consume = input({}, { res = RT.Fluid, fluids = { water }, amount = 0.5 }) }) },
        outputs = { output({ dough }, { create = output({}, { res = RT.Fluid, fluids = { water }, amount = 0.25 }) }) } }),
    recipe({ id = 'MakeWeirdBrick', tname = 'Make Weird Brick', category = 'BrickStuff', mod = 'MyBrickMod',
        inputs = { input({ scrap }, { count = 3 }) }, outputs = { output({ brick }, { count = 2 }) } }),
    recipe({ id = 'MakeMetalSheet', tname = 'Make Metal Sheet', category = 'Metalworking', learn = true,
        inputs = { input({ scrap }, { count = 4, tool = false }) }, outputs = { output({ metal }) },
        skills = { skill('MetalWelding', 3), skill('Blacksmith', 1) } }),
    recipe({ id = 'OpenUmbrella', category = 'Miscellaneous', tags = { 'InHandCraft', 'RightClickOnly' } }),
}
"""


class RecipeIndexTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='solo')
        self.h.load('solo', DOUBLES)
        self.h.load('solo', "Index = require('RadioSurvivor/RS_RecipeIndex')")

    def tearDown(self):
        self.h.close()

    def lua(self, code):
        return self.h.load('solo', code)

    def path(self):
        return self.h.file_root('solo') / 'batman_CoreAI' / 'recipes.json'

    def export(self):
        self.h.fire('solo', 'OnGameStart')
        raw = self.path().read_bytes()
        raw.decode('ascii')  # pure ASCII whatever the names
        return json.loads(raw)

    def recipes(self):
        return {r['id']: r for r in self.export()['recipes']}

    def test_vanilla_recipe_has_every_field(self):
        self.lua(WORLD)
        doc = self.export()
        self.assertEqual(doc['format'], 1)
        self.assertIsInstance(doc['written'], int)
        rec = {r['id']: r for r in doc['recipes']}['MakeSheetRope']
        self.assertEqual(rec, {
            'id': 'MakeSheetRope', 'name': 'Make Sheet Rope', 'category': 'Tailoring', 'job': 'tailoring',
            'inputs': [
                {'items': [{'item': 'Base.RippedSheets', 'name': 'Ripped Sheets'}], 'count': 2, 'tool': False},
                {'items': [{'item': 'Base.Needle', 'name': 'Needle'},
                           {'item': 'Base.SutureNeedle', 'name': 'Suture Needle'}], 'count': 1, 'tool': True},
                # float of the game (0.3f) rounded to the millilitre; energy, automation, any item/fluid skipped
                {'fluids': [{'fluid': 'Water', 'name': 'Water'}, {'fluid': 'TaintedWater', 'name': 'Tainted Water'}],
                 'amount': 0.3, 'tool': False}],
            'outputs': [{'items': [{'item': 'Base.SheetRope', 'name': 'Sheet Rope'}], 'count': 1},
                        {'fluids': [{'fluid': 'Dye', 'name': 'Dye'}], 'amount': 0.5}],
            'skills': [{'perk': 'Tailoring', 'level': 2}],
            'learn': False, 'learned_from': [], 'mod': ''})

    def test_fluids_of_container_lines(self):
        # '-fluid' under an input line is consumed from its container; '+fluid' under an input or output line is
        # created into it (CraftRecipe.java:605-657): neither is in getInputs/getOutputs.
        self.lua(WORLD)
        rec = self.recipes()['MakeDough']
        self.assertEqual(rec['inputs'], [
            {'items': [{'item': 'Base.Pot', 'name': 'Cooking Pot'}], 'count': 1, 'tool': True},
            {'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 1, 'tool': False},
            {'items': [{'item': 'Base.Bucket', 'name': 'Bucket'}], 'count': 1, 'tool': True},
            {'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 0.5, 'tool': False}])  # any-item container
        self.assertEqual(rec['outputs'], [
            {'items': [{'item': 'Base.Dough', 'name': 'Dough'}], 'count': 1},
            {'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 0.25},
            {'fluids': [{'fluid': 'Dye', 'name': 'Dye'}], 'amount': 2}])

    def test_mod_recipe_of_unknown_category_goes_to_makeshift(self):
        self.lua(WORLD)
        rec = self.recipes()['MakeWeirdBrick']
        self.assertEqual((rec['mod'], rec['category'], rec['job']), ('MyBrickMod', 'BrickStuff', 'makeshift'))
        self.assertEqual(rec['outputs'], [{'items': [{'item': 'MyMod.WeirdBrick', 'name': 'Weird Brick'}],
                                           'count': 2}])
        self.assertEqual(rec['skills'], [])

    def test_recipe_to_learn_lists_the_literature_that_teaches_it(self):
        self.lua(WORLD)
        rec = self.recipes()['MakeMetalSheet']
        self.assertTrue(rec['learn'])
        self.assertEqual(rec['learned_from'], ['Base.BookMetalWelding1', 'Base.MetalworkMag1'])
        self.assertEqual(rec['job'], 'smithing')
        self.assertEqual(rec['skills'], [{'perk': 'MetalWelding', 'level': 3}, {'perk': 'Blacksmith', 'level': 1}])

    def test_right_click_only_recipe_is_skipped_and_counted(self):
        self.lua(WORLD)
        ids = [r['id'] for r in self.export()['recipes']]
        self.assertEqual(ids, ['MakeDough', 'MakeMetalSheet', 'MakeSheetRope', 'MakeWeirdBrick'])  # umbrella skipped
        line = [x for x in self.h.logs('solo') if 'recipes written' in x]
        self.assertEqual(len(line), 1, self.h.logs('solo'))
        self.assertRegex(line[0], r'4 recipes written to batman_CoreAI/recipes\.json \(1 hidden skipped\), '
                                  r'\d+ bytes, \d+ ms')
        self.assertIn(f"{self.path().stat().st_size} bytes", line[0])

    def test_written_once_per_session(self):
        self.lua(WORLD)
        self.export()
        self.h.fire('solo', 'OnServerStarted')
        self.h.fire('solo', 'OnGameStart')
        self.assertEqual(len([x for x in self.h.logs('solo') if 'recipes written' in x]), 1)

    def test_other_language_names_come_from_ids(self):
        self.lua(WORLD + "\nLANG = FR")
        rec = self.recipes()['MakeSheetRope']
        self.assertEqual(rec['name'], 'Make Sheet Rope')
        self.assertEqual(rec['inputs'][0]['items'][0]['name'], 'Ripped Sheets')
        self.assertEqual(rec['inputs'][2]['fluids'][1]['name'], 'Tainted Water')
        self.assertEqual(self.recipes()['MakeMetalSheet']['outputs'][0]['items'][0]['name'], 'Sheet Metal')

    def test_untranslated_name_is_split_from_the_id(self):
        self.lua("""RECIPES = { recipe({ id = 'Forge_Bar_HalfX2', category = 'Blade' }),
                               recipe({ id = 'MakeTVStand', category = 'carpentry' }) }""")
        recs = self.recipes()
        self.assertEqual(recs['Forge_Bar_HalfX2']['name'], 'Forge Bar Half X 2')
        self.assertEqual(recs['MakeTVStand']['name'], 'Make TV Stand')
        self.assertEqual(recs['MakeTVStand']['job'], 'carpentry')  # category compared without case
        self.assertEqual(recs['Forge_Bar_HalfX2']['inputs'], [])  # empty table = empty array

    def test_json_escaping_quotes_backslashes_and_non_ascii(self):
        # Lua 5.1 strings are UTF-8 bytes: e acute (2 bytes), a 4-byte emoji (surrogate pair in JSON).
        self.lua(r"""RECIPES = { recipe({ id = 'Odd', category = 'Cooking',
            tname = 'Say "hi" \\ caf\195\169 \240\159\152\128' .. string.char(10, 1) }) }""")
        raw = (self.export(), self.path().read_text(encoding='ascii'))[1]
        u = chr(92) + 'u'  # JSON unicode escape, spelled out
        self.assertIn(r'"Say \"hi\" \\ caf' + u + '00e9 ' + u + 'd83d' + u + r'de00\n' + u + '0001"', raw)
        self.assertEqual(json.loads(raw)['recipes'][0]['name'],
                         'Say "hi" \\ caf' + chr(0xE9) + ' ' + chr(0x1F600) + '\n\x01')

    def test_json_of_kahlua_utf16_strings(self):
        # In game a string is UTF-16 units (CA_Codec): e acute is one unit of code 233.
        got = self.lua(r"""local Codec = require('CoreAI/CA_Codec'); Codec._utf16 = true
            local s = require('RadioSurvivor/RS_Json').encode({ 'caf' .. string.char(233) })
            Codec._utf16 = nil; return s""")
        self.assertEqual(got, '["caf' + chr(92) + 'u00e9"]')

    def test_unwritable_file_logs_an_error(self):
        self.lua(WORLD + "\ngetFileWriter = function() return nil end")
        self.assertIsNone(self.h.eval('solo', "Index.export()"))
        self.assertTrue(any('ERROR: cannot write Zomboid/Lua/batman_CoreAI/recipes.json' in x
                            for x in self.h.logs('solo')))


class RecipeJobsTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='solo')
        self.h.load('solo', "Jobs = require('RadioSurvivor/RS_RecipeJobs')")

    def tearDown(self):
        self.h.close()

    def test_every_category_belongs_to_one_job(self):
        pairs = self.h.eval('solo', """(function()
            local out = {}
            for job, cats in pairs(Jobs.JOBS) do
                for _, c in ipairs(cats) do out[#out + 1] = job .. '=' .. string.lower(c) end
            end
            return table.concat(out, ',') end)()""").split(',')
        cats = [p.split('=')[1] for p in pairs]
        self.assertEqual(len(cats), len(set(cats)))

    def test_vanilla_categories_and_default(self):
        for category, job in [('Tailoring', 'tailoring'), ('Cooking', 'cooking'), ('Masonry', 'carpentry'),
                              ('Blacksmithing', 'smithing'), ('Electrical', 'electrical'), ('Farming', 'farming'),
                              ('Medical', 'medical'), ('Weaponry', 'weapons'), ('Glassmaking', 'pottery'),
                              ('Miscellaneous', 'makeshift'), ('Packing', 'makeshift'), ('Unheard', 'makeshift')]:
            self.assertEqual(self.h.eval('solo', f"Jobs.of('{category}')"), job, category)
        self.assertEqual(self.h.eval('solo', "Jobs.of(nil)"), 'makeshift')

    def test_a_job_is_added_by_data(self):
        self.h.load('solo', "Jobs.JOBS.brewing = { 'Brewing' }; Jobs.reset()")
        self.assertEqual(self.h.eval('solo', "Jobs.of('brewing')"), 'brewing')


if __name__ == '__main__':
    unittest.main()
