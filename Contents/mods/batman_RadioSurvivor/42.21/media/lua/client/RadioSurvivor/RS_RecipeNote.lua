--[[
RadioSurvivor: the notebook entry of a recipe given by a voice (E27-T04, ADR recettes-radio D09, D10). Client only,
presentation only. The authority stores a Radio line of kind "recipe", text "<id>|<1 learned from the voice | 0>"
(RS_RecipeDelivery); this module reads the recipe from the player's own game (ScriptManager.getCraftRecipe), with the
same reading rules as the recipe index (RS_RecipeCatalog.describe: names the game gives in the player's language,
English or the id in words for an untranslated mod), and words it: result, ingredients, fluids, tools, skills, and
"learned" or "must be learned". A recipe unknown to this game: its id in words.
Fixed words: IGUI_RS_Recipe* (Translate/<LANG>/IG_UI.json). ASCII only (Kahlua lexer).
]]
local Catalog = require 'RadioSurvivor/RS_RecipeCatalog'

local Note = {}

local function tr(key, ...) return getText('IGUI_RS_' .. key, ...) end

local function amount(value) return string.format('%g', value) end

local function choices(line)
    local names = {}
    for _, c in ipairs(line.items or line.fluids or {}) do names[#names + 1] = c.name end
    return table.concat(names, ' ' .. tr('RecipeOr') .. ' ')
end

local function quantity(line)
    if line.fluids then return tr('RecipeLitres', amount(line.amount), choices(line)) end
    return amount(line.count) .. ' x ' .. choices(line)
end

local function joined(lines, word)
    local parts = {}
    for _, line in ipairs(lines) do parts[#parts + 1] = word(line) end
    return table.concat(parts, ', ')
end

local function perkName(id)
    local perk = Perks.FromString(id)
    if perk == nil or perk == Perks.MAX then return id end
    return PerkFactory.getPerkName(perk)
end

-- Words of a recipe record (RS_RecipeCatalog.describe), learned now from the voice or not.
local function words(rec, learned)
    local used, tools = {}, {}
    for _, line in ipairs(rec.inputs) do
        if line.tool then tools[#tools + 1] = line else used[#used + 1] = line end
    end
    local parts = { rec.name, tr('RecipeMakes', joined(rec.outputs, quantity)) }
    if #used > 0 then parts[#parts + 1] = tr('RecipeNeeds', joined(used, quantity)) end
    if #tools > 0 then parts[#parts + 1] = tr('RecipeTools', joined(tools, choices)) end
    if #rec.skills > 0 then
        parts[#parts + 1] = joined(rec.skills, function(s) return tr('RecipeSkill', perkName(s.perk), s.level) end)
    end
    if learned then
        parts[#parts + 1] = tr('RecipeLearned')
    elseif rec.learn then
        parts[#parts + 1] = tr('RecipeMustLearn')
    end
    return table.concat(parts, '; ')
end

-- Text of a "recipe" Radio line in the player's language.
function Note.text(lineText)
    local id, flag = string.match(tostring(lineText or ''), '^(.-)|([01])$')
    id = id or tostring(lineText or '')
    local recipe = getScriptManager():getCraftRecipe(id)
    if not recipe then return Catalog.idName(id) end
    return words(Catalog.describe(recipe), flag == '1')
end

return Note
