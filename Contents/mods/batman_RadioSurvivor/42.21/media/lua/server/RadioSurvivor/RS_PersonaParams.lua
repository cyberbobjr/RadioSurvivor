-- Radio Survivor : kinds of the values a voice sheet section may carry (E20-T03, ADR D02/D04).
-- A mission template declares its own parameters (RC_Missions, declaration params = { key = '<kind>' }) and a reward
-- kind its parameter (RS_Rewards.KINDS); RS_Persona checks every such value here, one validator per kind. Adding a
-- kind = one Params.register call, without touching the sheet reader.
-- validator(value, ctx) -> parsed value, or nil and the reason (English, logged with the line of the sheet).
-- ctx (built by RS_Persona): places (id -> place of the sheet), categories (id -> category: shared catalogue and
-- categories of the sheet), skills (list of the skills a lesson may teach).
-- ASCII only (Kahlua lexer).
if isClient() then return end

local Params = {}

local validators = {}
local MAX_NUMBER = 999999

function Params.register(kind, validator)
    validators[kind] = validator
end

function Params.known(kind)
    return validators[kind] ~= nil
end

-- Parsed value of `value` for this kind, or nil and the reason.
function Params.check(kind, value, ctx)
    local validator = validators[kind]
    if not validator then return nil, "unknown parameter kind '" .. tostring(kind) .. "'" end
    return validator(value, ctx)
end

local function wholeNumber(text)
    if not string.match(text, "^[0-9]+$") or string.len(text) > 6 then return nil end
    return tonumber(text)
end

Params.register("count", function(value)
    local n = wholeNumber(value)
    if not n then return nil, "bad count '" .. value .. "' (whole number from 0 to " .. tostring(MAX_NUMBER) .. ")" end
    return n
end)

-- "4" (exactly 4) or "2-4" (2 to 4), lowest first.
Params.register("range", function(value)
    local low, high = string.match(value, "^([0-9]+)%-([0-9]+)$")
    if not low then low, high = value, value end
    low, high = wholeNumber(low), wholeNumber(high)
    if not low or not high or low > high then
        return nil, "bad range '" .. value .. "' (whole number or range lowest first, e.g. 2-4)"
    end
    return { min = low, max = high }
end)

Params.register("category", function(value, ctx)
    if not ctx.categories[value] then return nil, "unknown category '" .. value .. "'" end
    return value
end)

Params.register("place", function(value, ctx)
    if not ctx.places[value] then return nil, "unknown place '" .. value .. "'" end
    return value
end)

Params.register("text", function(value)
    return value
end)

Params.register("skill", function(value, ctx)
    for _, skill in ipairs(ctx.skills) do
        if skill == value then return value end
    end
    return nil, "unknown skill '" .. value .. "' (expected " .. table.concat(ctx.skills, ", ") .. ")"
end)

return Params
