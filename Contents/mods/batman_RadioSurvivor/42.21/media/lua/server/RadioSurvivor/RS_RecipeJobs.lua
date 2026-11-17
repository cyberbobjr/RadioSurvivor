-- Jobs of the recipe index (E27-T01, ADR recettes-radio D02): a job groups craftRecipe categories of the game
-- (CraftRecipe:getCategory, raw script value). Extended by data only: add a category to a list, or a job to JOBS.
-- A category listed nowhere (mod recipe with its own category, vanilla Miscellaneous...) goes to DEFAULT.
-- Categories are compared without case (mods write "cooking" or "Cooking"). A category belongs to one job only.
-- Mapping and reasons: docs/specifications-techniques/index-recettes.md. ASCII only (Kahlua lexer).
local Const = require "RadioSurvivor/RadioSurvivor_Const"

local Jobs = {}

Jobs.DEFAULT = 'makeshift'

-- Job id -> categories (vanilla 42.22 craftRecipe categories, media/scripts).
Jobs.JOBS = {
    tailoring = { 'Tailoring' },
    cooking = { 'Cooking' },
    carpentry = { 'Carpentry', 'Carving', 'Masonry' },
    smithing = { 'Blacksmithing', 'Metalworking', 'Tools', 'Blade', 'Cookware', 'Armor', 'Assembly' },
    electrical = { 'Electrical' },
    mechanics = { 'Mechanics' },
    farming = { 'Farming' },
    medical = { 'Medical' },
    weapons = { 'Weaponry' },
    pottery = { 'Pottery', 'Glassmaking' },
    makeshift = {},
}

local byCategory = nil

local function index()
    if byCategory then return byCategory end
    byCategory = {}
    local ids = {}
    for id in pairs(Jobs.JOBS) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _, category in ipairs(Jobs.JOBS[id]) do
            local key = string.lower(category)
            if byCategory[key] and byCategory[key] ~= id then
                Const.log("recipes: category '" .. category .. "' listed in jobs '" .. byCategory[key]
                    .. "' and '" .. id .. "'; kept in '" .. byCategory[key] .. "'")
            else
                byCategory[key] = id
            end
        end
    end
    return byCategory
end

-- Job id of a recipe category (nil or unknown: DEFAULT).
function Jobs.of(category)
    if type(category) ~= 'string' then return Jobs.DEFAULT end
    return index()[string.lower(category)] or Jobs.DEFAULT
end

-- Forget the reverse table (tests that change JOBS).
function Jobs.reset()
    byCategory = nil
end

return Jobs
