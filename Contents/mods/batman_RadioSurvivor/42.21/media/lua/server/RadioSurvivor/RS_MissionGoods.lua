-- Goods asked by a radio voice mission (E20-T16, ADR D04). Authority only.
-- Any mission template that declares the strategy askFor(m, types, quantity) (RC_Missions: deliver) takes the goods
-- of its sheet section: items=<category> (the item types of that category, RS_Categories: [category] section of the
-- sheet first, else the shared catalogue) and quantity= (a number or a range, drawn here when the mission starts and
-- kept on the mission). A key left out hands nil to the template, which keeps its own value (deliver: the list and
-- the quantity of RC_MissionConfig). The set-up is registered for that declaration
-- (RS_MissionVoice.registerDeclaredSetup): check refuses the start when the category gives no item type (no_goods),
-- apply hands the goods to the template on the new mission, before it is accepted and saved.
-- ASCII only (Kahlua lexer).
if isClient() then return end
local Voice = require 'RadioSurvivor/RS_MissionVoice'
local Missions = require 'RadioSurvivorCore/RC_Missions'
local Categories = require 'RadioSurvivor/RS_Categories'

local G = {}

local function defaultRandom(n)
    return ZombRand(n)
end

local random = defaultRandom

-- Generator of the quantity draw (random(n) -> 0..n-1; tests inject a seeded one); nil restores ZombRand.
function G.setRandom(fn)
    random = fn or defaultRandom
end

local function paramsOf(section)
    return type(section) == 'table' and type(section.params) == 'table' and section.params or {}
end

-- Item types named by items= of the section, or nil without that key.
function G.types(sheet, section)
    local id = paramsOf(section).items
    if id == nil then return nil end
    return Categories.types(Categories.of(sheet, id))
end

-- Quantity drawn in quantity= of the section ({ min, max }, RS_PersonaParams range; a fixed number is not drawn), or
-- nil without that key.
function G.quantity(section)
    local range = paramsOf(section).quantity
    if type(range) ~= 'table' then return nil end
    if range.max <= range.min then return range.min end
    return range.min + random(range.max - range.min + 1)
end

-- Set-up of the declaration askFor (RS_MissionVoice): refused when the category gives no item type.
function G.check(sheet, section)
    local types = G.types(sheet, section)
    if types ~= nil and #types == 0 then return false, 'no_goods' end
    return true
end

-- Goods of the section handed to the template of the new mission (donor unused: same contract as every set-up).
function G.apply(m, sheet, donor, section)
    Missions.template(m).askFor(m, G.types(sheet, section), G.quantity(section))
end

Voice.registerDeclaredSetup('askFor', {check = G.check, apply = G.apply})

return G
