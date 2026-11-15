-- Item categories of the radio voices (E20-T03, E20-T16, ADR D04). Authority only.
-- One resolver for every reader of a category id named by a sheet: the cache reward (RS_Reward_Cache, pool entry
-- cache:<category>) and the goods of a voice mission (RS_MissionGoods, items=<category> of a [mission] section).
-- A [category <id>] section of the sheet comes first, else the shared catalogue personas/_categories.txt
-- (RS_Personas.rules). A category is { id, items = { { type = 'Module.Type', min, max } } } (RS_Persona).
-- ASCII only (Kahlua lexer).
if isClient() then return end

local Categories = {}

-- Category of this id for the sheet (its own section first, else the shared catalogue), or nil.
function Categories.of(sheet, id)
    local own = type(sheet) == 'table' and type(sheet.categories) == 'table' and sheet.categories[id] or nil
    if own then return own end
    return require('RadioSurvivor/RS_Personas').rules().categories[id]
end

-- Item types of a category, in the order of its lines, each once.
function Categories.types(category)
    local out, seen = {}, {}
    for _, item in ipairs(type(category) == 'table' and type(category.items) == 'table' and category.items or {}) do
        if type(item.type) == 'string' and not seen[item.type] then
            seen[item.type] = true
            out[#out + 1] = item.type
        end
    end
    return out
end

return Categories
