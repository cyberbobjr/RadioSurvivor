-- Ordered points of a radio voice mission (E20-T13, ADR D02, D04). Authority only.
-- Any mission template that declares the strategy alongPoints(m, points) -> ok, reason (RC_Missions; route: places
-- to cross in order) works on the places named in order by the parameter points= of its sheet section (kind `places`
-- of RS_PersonaParams: places of the sheet with use=target). The set-up is registered for that declaration
-- (RS_MissionVoice.registerDeclaredSetup): check refuses the start before any mission exists (no_points: a name of
-- the list is not a place of the sheet with use=target; else the template's own reason, alongPoints run on a scratch
-- table), apply hands the places { id, label, x, y, z }, in the order of the list, to the template on the new
-- mission, before it is accepted and saved. ASCII only (Kahlua lexer).
if isClient() then return end
local Voice = require 'RadioSurvivor/RS_MissionVoice'
local Persona = require 'RadioSurvivor/RS_Persona'
local Missions = require 'RadioSurvivorCore/RC_Missions'

local W = {}

-- Places of the sheet named by the section's points= in that order, or nil when one is missing.
function W.points(sheet, section)
    local params = type(section) == 'table' and type(section.params) == 'table' and section.params or {}
    if type(params.points) ~= 'table' then return nil end
    local byId = {}
    for _, p in ipairs(Persona.placesFor(sheet, 'target')) do byId[p.id] = p end
    local out = {}
    for i, id in ipairs(params.points) do
        out[i] = byId[id]
        if not out[i] then return nil end
    end
    return out
end

local function check(sheet, section)
    local points = W.points(sheet, section)
    if not points then return false, 'no_points' end
    local _, t = Missions.voiceTemplate(section.type)
    if not t then return false, 'bad_template' end
    local ok, why = t.alongPoints({}, points)
    if not ok then return false, why or 'no_points' end
    return true
end

local function apply(m, sheet, donor, section)
    Missions.template(m).alongPoints(m, W.points(sheet, section))
end

Voice.registerDeclaredSetup('alongPoints', {check = check, apply = apply})

return W
