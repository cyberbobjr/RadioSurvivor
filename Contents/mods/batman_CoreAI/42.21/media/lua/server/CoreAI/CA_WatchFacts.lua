if isClient() then return end
--[[
Facts seen during a watch (mission template `watch`, E20-T14, ADR D10): registry of the fact sources. Authority only.
One file per source in server/CoreAI/WatchFacts/, registered at load (the game runs every server file of
the mod, sub-folders included; a bench requires them); the template asks the registry, never a source by name, so
adding a fact is one new file.

    Facts.register(name, source)    source = { line = '<plain English line>', seen = function(m, spot) -> boolean }
                                    name: key of m.facts ([a-z_]); line: told to the voice's model once the fact is
                                    recorded, never a coordinate; seen: true when the fact holds now at the spot
                                    { x, y, z } of the watch m (m.watchFrom: world age, game hours, the current watch
                                    started at). Registering a name again replaces its source.
    Facts.observe(m, spot) -> boolean   records in m.facts each fact seen now (once per watch); true when one is new
    Facts.lines(m) -> { line }      lines of the facts recorded, in the order of the names
ASCII only (Kahlua lexer).
]]
local Facts = {}

local sources, order = {}, {}

function Facts.register(name, source)
    if sources[name] == nil then
        order[#order + 1] = name
        table.sort(order)
    end
    sources[name] = source
    return source
end

function Facts.observe(m, spot)
    if type(m.facts) ~= 'table' then m.facts = {} end
    local changed = false
    for _, name in ipairs(order) do
        if not m.facts[name] and sources[name].seen(m, spot) then m.facts[name], changed = true, true end
    end
    return changed
end

function Facts.lines(m)
    local out = {}
    if type(m.facts) ~= 'table' then return out end
    for _, name in ipairs(order) do
        if m.facts[name] then out[#out + 1] = sources[name].line end
    end
    return out
end

return Facts
