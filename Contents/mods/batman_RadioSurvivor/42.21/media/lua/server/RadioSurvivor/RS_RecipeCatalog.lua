-- Craft recipes really loaded by the game, as plain records (E27-T01, ADR recettes-radio D02, D11). Reads the
-- scripts only (no file, no event): RS_RecipeIndex writes what this returns. Java API, sources 42.22:
--   ScriptManager.getAllCraftRecipes (ScriptManager.java:985): every craftRecipe script, vanilla and active mods,
--     a mod override replacing the vanilla script of the same name (entity build recipes are not in this list);
--   CraftRecipe (scripting/entity/components/crafting/CraftRecipe.java): getName 146, getTranslationName 150
--     (Translator.getRecipeName at load, the name itself when untranslated), getCategory 228 ("Miscellaneous" when
--     empty), getTags 236 (strings as written), getInputs 261, getOutputs 265, needToBeLearn 185, isVanilla 128,
--     getModID 132, getRequiredSkillCount 952 / getRequiredSkill 956 -> RequiredSkill getPerk 1592 / getLevel 1596;
--   InputScript: getResourceType 183, isAcceptsAnyItem 480, isAcceptsAnyFluid 484, isAutomationOnly 496, isKeep 212,
--     isTool 216, getIntAmount 384, getAmount 388, getPossibleInputItems 110 (item scripts, tags resolved),
--     getPossibleInputFluids 123, getConsumeFromItemScript 163 / getCreateToItemScript 155 (the '-' and '+' lines
--     under an input line, not in getInputs: CraftRecipe.java:605-638);
--   OutputScript: getResourceType 98, isAutomationOnly 139, getIntAmount 106, getAmount 110,
--     getPossibleResultItems 143, getPossibleResultFluids 151, getCreateToItemScript 81 ('+' line, :641-650);
--   Fluid (entity/components/fluids/Fluid.java): getFluidTypeString 285, getDisplayName 301;
--   Item (scripting/objects/Item.java): getFullName 908, getDisplayName 514, getLearnedRecipes 3812 (nullable);
--   PerkFactory.Perk getId 175; Translator.getLanguage 447 / getDefaultLanguage 583, Language.toString = its name.
-- Skip rule: a recipe tagged RightClickOnly is hidden by the crafting window (HandcraftLogic.java:184) and done from
-- a context menu only (umbrella, tissue, dice...): it is not in the index. Craft recipes have no other hidden flag.
-- Lines: items (every possible item listed) and fluids (every possible fluid, amount in litres); energy lines,
-- automation-only lines, "any item" and "any fluid" lines skipped (the fluid of an "any item" container is kept).
-- Names: English only when the game language is the default (English); else,
-- or when the game has no name, the id split on its capitals and underscores.
-- ASCII only (Kahlua lexer).
local Jobs = require "RadioSurvivor/RS_RecipeJobs"

local Catalog = {}

Catalog.HIDDEN_TAG = 'RightClickOnly'

local function each(list, fn)
    if list == nil then return end
    for i = 0, list:size() - 1 do fn(list:get(i)) end
end

-- "MakeTinFoilHat" -> "Make Tin Foil Hat", "Base.Forge_Bar_Half" -> "Forge Bar Half".
function Catalog.idName(id)
    local s = tostring(id or '')
    s = s:gsub('^.*%.', '')
    s = s:gsub('_+', ' ')
    s = s:gsub('(%l)(%u)', '%1 %2')
    s = s:gsub('(%u)(%u%l)', '%1 %2')
    s = s:gsub('(%a)(%d)', '%1 %2')
    s = s:gsub('%s+', ' ')
    return (s:gsub('^ ', ''):gsub(' $', ''))
end

-- True when the names the game gives are English (game language = default language).
function Catalog.englishNames()
    return tostring(Translator.getLanguage()) == tostring(Translator.getDefaultLanguage())
end

local function name(given, id, english)
    if english and type(given) == 'string' and given ~= '' and given ~= id then return given end
    return Catalog.idName(id)
end

local function hidden(recipe)
    local found = false
    each(recipe:getTags(), function(tag) if tag == Catalog.HIDDEN_TAG then found = true end end)
    return found
end

-- Every possible item of a line: { { item = full type, name = English name } }, nil when there is none.
local function itemsOf(list, english)
    local out = {}
    each(list, function(item)
        local full = item:getFullName()
        out[#out + 1] = { item = full, name = name(item:getDisplayName(), full, english) }
    end)
    return #out > 0 and out or nil
end

-- Every possible fluid of a line: { { fluid = id, name = English name } }, nil when there is none.
local function fluidsOf(list, english)
    local out = {}
    each(list, function(fluid)
        local id = fluid:getFluidTypeString()
        out[#out + 1] = { fluid = id, name = name(fluid:getDisplayName(), id, english) }
    end)
    return #out > 0 and out or nil
end

-- Litres of a fluid line (Java float: 0.3f reads 0.30000001...), rounded to the millilitre.
local function litres(amount)
    return math.floor(amount * 1000 + 0.5) / 1000
end

local function fluidInput(script, english)
    if script == nil or script:getResourceType() ~= ResourceType.Fluid or script:isAcceptsAnyFluid() then return nil end
    local fluids = fluidsOf(script:getPossibleInputFluids(), english)
    return fluids and { fluids = fluids, amount = litres(script:getAmount()), tool = false } or nil
end

local function fluidOutput(script, english)
    if script == nil or script:getResourceType() ~= ResourceType.Fluid then return nil end
    local fluids = fluidsOf(script:getPossibleResultFluids(), english)
    return fluids and { fluids = fluids, amount = litres(script:getAmount()) } or nil
end

local function add(list, entry)
    if entry then list[#list + 1] = entry end
end

-- Input entries in line order, and the fluids created into input containers ('+' under an input line).
local function inputs(recipe, english)
    local out, created = {}, {}
    each(recipe:getInputs(), function(input)
        if input:isAutomationOnly() then return end
        local kind = input:getResourceType()
        if kind == ResourceType.Fluid then
            add(out, fluidInput(input, english))
            return
        end
        if kind ~= ResourceType.Item then return end
        if not input:isAcceptsAnyItem() then
            local items = itemsOf(input:getPossibleInputItems(), english)
            if items then
                add(out, { items = items, count = input:getIntAmount(), tool = input:isKeep() or input:isTool() })
            end
        end
        add(out, fluidInput(input:getConsumeFromItemScript(), english))
        add(created, fluidOutput(input:getCreateToItemScript(), english))
    end)
    return out, created
end

-- Output entries in line order ('+' fluid under an output line right after it), then the fluids of `created`.
local function outputs(recipe, english, created)
    local out = {}
    each(recipe:getOutputs(), function(output)
        if output:isAutomationOnly() then return end
        local kind = output:getResourceType()
        if kind == ResourceType.Fluid then
            add(out, fluidOutput(output, english))
            return
        end
        if kind ~= ResourceType.Item then return end
        local items = itemsOf(output:getPossibleResultItems(), english)
        if items then add(out, { items = items, count = output:getIntAmount() }) end
        add(out, fluidOutput(output:getCreateToItemScript(), english))
    end)
    for _, entry in ipairs(created) do out[#out + 1] = entry end
    return out
end

local function skills(recipe)
    local out = {}
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        out[#out + 1] = { perk = skill:getPerk():getId(), level = skill:getLevel() }
    end
    return out
end

-- Recipe name -> sorted full types of the items that teach it (Item:getLearnedRecipes: magazines, books...).
function Catalog.teachers(scriptManager)
    local by = {}
    each(scriptManager:getAllItems(), function(item)
        each(item:getLearnedRecipes(), function(recipeName)
            local list = by[recipeName]
            if not list then list = {}; by[recipeName] = list end
            list[#list + 1] = item:getFullName()
        end)
    end)
    for _, list in pairs(by) do table.sort(list) end
    return by
end

local function record(recipe, english, teachers)
    local id = recipe:getName()
    local category = recipe:getCategory()
    local ins, created = inputs(recipe, english)
    return {
        id = id,
        name = name(recipe:getTranslationName(), id, english),
        category = category,
        job = Jobs.of(category),
        inputs = ins,
        outputs = outputs(recipe, english, created),
        skills = skills(recipe),
        learn = recipe:needToBeLearn() == true,
        learned_from = teachers[id] or {},
        mod = recipe:isVanilla() and '' or (recipe:getModID() or ''),
    }
end

-- Records of every visible craft recipe, sorted by id, and the number of hidden recipes skipped.
function Catalog.read(scriptManager)
    local english = Catalog.englishNames()
    local teachers = Catalog.teachers(scriptManager)
    local out, skipped = {}, 0
    each(scriptManager:getAllCraftRecipes(), function(recipe)
        if hidden(recipe) then
            skipped = skipped + 1
        else
            out[#out + 1] = record(recipe, english, teachers)
        end
    end)
    table.sort(out, function(a, b) return a.id < b.id end)
    return out, skipped
end

return Catalog
