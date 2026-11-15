-- Target place of a radio voice mission (E20-T09, ADR D02, D04). Authority only.
-- Any mission template that declares the strategy aimAt(m, place, params) -> ok, reason (CA_Missions; barricade: the
-- building to barricade) works on the place named by the common key target= of its sheet section (RS_Persona: a
-- place of the sheet with use=target). The set-up is registered for that declaration
-- (RS_MissionVoice.registerDeclaredSetup): check refuses the start before any mission exists (no_target: the section
-- names no target place of the sheet; else the template's own reason, aimAt run on a scratch table), apply hands the
-- place { id, label, x, y, z } and the section's parameters to the template on the new mission, before it is accepted
-- and saved. ASCII only (Kahlua lexer).
if isClient() then return end
local Voice = require 'RadioSurvivor/RS_MissionVoice'
local Persona = require 'RadioSurvivor/RS_Persona'
local Missions = require 'CoreAI/CA_Missions'

local T = {}

-- Place of the sheet named by the section's target= (use=target), or nil.
T.place = Persona.targetOf

local function paramsOf(section)
    return type(section) == 'table' and type(section.params) == 'table' and section.params or {}
end

local function check(sheet, section)
    local place = T.place(sheet, section)
    if not place then return false, 'no_target' end
    local _, t = Missions.voiceTemplate(section.type)
    if not t then return false, 'bad_template' end
    local ok, why = t.aimAt({}, place, paramsOf(section))
    if not ok then return false, why or 'no_place' end
    return true
end

local function apply(m, sheet, donor, section)
    Missions.template(m).aimAt(m, T.place(sheet, section), paramsOf(section))
end

Voice.registerDeclaredSetup('aimAt', {check = check, apply = apply})

return T
