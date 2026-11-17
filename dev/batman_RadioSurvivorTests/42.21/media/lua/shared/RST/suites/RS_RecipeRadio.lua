--[[
rs.reciperadio - recipe given by a voice, in game (E27-T04, ADR recettes-radio D04 to D07, D09). Authority only (solo,
or RST.server from an admin client). Real Java: GameTime.getWorldAgeHours, ScriptManager.getCraftRecipe of a vanilla
recipe that must be learned (SewClothSatchel, Tailoring, media/scripts/generated/recipes/recipes_tailoring.txt),
IsoGameCharacter.learnRecipe / isRecipeKnown / getKnownRecipes, sendSyncPlayerFields.
Steps: a search of a voice with a one-hour delay is kept and not ready; delivery at reputation "good" teaches the
recipe and writes the "recipe" line of the notebook. The recipe, the search and the line are put back at the end.
Outside the game: tests/radiosurvivor/test_recipe_delivery.py (doubles).
]]
require 'RST/RST'
require "RST/RST_ModRadioSurvivor"
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local RECIPE = 'SewClothSatchel'
local KHZ = 199700
local VOICE = 'rst-recipe-voice'

local function run(t)
    if isClient() then t:skip('authority only') end
    local Searches = require 'RadioSurvivor/RS_RecipeSearches'
    local Delivery = require 'RadioSurvivor/RS_RecipeDelivery'
    local Log = require 'RadioSurvivor/RS_RadioLog'
    local History = require 'CoreAI/CA_History'
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local cid = Log.characterOf(p)
    if not cid then t:skip('no notebook character for the player') end
    if not getScriptManager():getCraftRecipe(RECIPE) then t:skip('vanilla recipe ' .. RECIPE .. ' absent') end
    local known = p:isRecipeKnown(RECIPE)
    t:defer(function()
        if not known then p:getKnownRecipes():remove(RECIPE); sendSyncPlayerFields(p, 1) end
    end, 'forget the recipe')
    t:defer(function() Searches.clear(cid, VOICE) end, 'drop the search')
    t:defer(function()
        local radio = History.radio(cid, false)
        for i, f in ipairs(radio and radio.frequencies or {}) do
            if f.khz == KHZ then table.remove(radio.frequencies, i); History.dirty = true; break end
        end
    end, 'drop the notebook line')

    t:ok(Searches.store(cid, VOICE, 'hour', {ids = {RECIPE}, keywords = {'satchel'}}), 'search not kept')
    local field, ready = Searches.field(cid, VOICE)
    t:eq({true, false}, {field ~= nil, ready}, 'search kept and not ready yet')

    local sheet = {id = VOICE, help = {jobs = {'tailoring'}, from = 'neutral', delay = 'hour'}}
    local learned = Delivery.deliver({cid = cid, khz = KHZ, sheet = sheet, player = p, level = 'good'}, {RECIPE})
    t:eq(not known, learned[RECIPE] == true, 'learned flag')
    t:ok(p:isRecipeKnown(RECIPE), 'recipe not known after the delivery at good')
    local radio = History.radio(cid, false)
    local line
    for _, f in ipairs(radio and radio.frequencies or {}) do
        if f.khz == KHZ then line = f.lines[#f.lines] end
    end
    t:eq('recipe', line and line.kind, 'no recipe line in the notebook')
end

RST.suite("rs.reciperadio", {tags = {"server", "world"}, testTimeoutMs = 60000}, function(s)
    s.test('a delayed search is kept, a delivery at good teaches the recipe and notes it', run)
end)
