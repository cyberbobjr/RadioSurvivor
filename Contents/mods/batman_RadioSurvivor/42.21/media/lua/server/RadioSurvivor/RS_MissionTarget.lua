-- Target place of a radio voice mission (E20-T09, ADR D02, D04). Authority only.
-- Any mission template that declares the strategy aimAt(m, place, params) -> ok, reason (CA_Missions; barricade: the
-- building to barricade) works on the objective of its sheet section, resolved once per start by RS_MissionAim
-- (E25-T01: target= names a shared place or a distance; aim = the place { id, label, x, y, z } it resolves to, a
-- building drawn for a zone or a distance, E25-T02). The
-- set-up is registered for that declaration (RS_MissionVoice.registerDeclaredSetup): check refuses the start before
-- any mission exists (the template's own reason, aimAt run on a scratch table; E25-T02: the objective always exists
-- here, a section without target= being near and an objective that cannot be drawn refusing the start before),
-- apply hands the place and the section's parameters to the template on the new mission, before it is accepted and
-- saved. ASCII only (Kahlua lexer).
if isClient() then return end
local Voice = require 'RadioSurvivor/RS_MissionVoice'
local Missions = require 'CoreAI/CA_Missions'

local T = {}

local function paramsOf(section)
    return type(section) == 'table' and type(section.params) == 'table' and section.params or {}
end

local function check(sheet, section, aim)
    local _, t = Missions.voiceTemplate(section.type)
    if not t then return false, 'bad_template' end
    local ok, why = t.aimAt({}, aim, paramsOf(section))
    if not ok then return false, why or 'no_place' end
    return true
end

local function apply(m, sheet, donor, section, aim)
    Missions.template(m).aimAt(m, aim, paramsOf(section))
end

Voice.registerDeclaredSetup('aimAt', {check = check, apply = apply})

return T
