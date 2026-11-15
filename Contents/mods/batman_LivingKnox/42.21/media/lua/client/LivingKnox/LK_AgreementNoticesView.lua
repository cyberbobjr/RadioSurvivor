--[[
Living Knox: on-screen notices of its agreements and incidents, player side (E09-T05, E09-T06; moved out of
the notebook by E21-T04). Commands "agreement" and "incident" of the network module LivingKnox, sent by
server/LivingKnox/LK_AgreementNotices.lua to the connected players of the team (solo: View.receive called directly).

  agreement   halo "truce / alliance with <group> now in force", once per agreement revision;
  incident    halo of the leader's decision (maintain, repair with the category asked, break), once per incident.

Texts: IGUI_LK_Agreement_*, IGUI_LK_AgreementUnnamed_*, IGUI_LK_Incident_*, IGUI_LK_IncidentGroup,
IGUI_LK_RepairCategory_*.
]]
if isServer() then return end
require 'LivingKnox/LK_Core'

local View = LivingKnox.AgreementNoticesView or {}
LivingKnox.AgreementNoticesView = View
View.MODULE = 'LivingKnox'
View.agreementsShown = View.agreementsShown or {}
View.incidentsShown = View.incidentsShown or {}

local function agreement(args, p)
    if type(args.id) ~= 'string' or (args.kind ~= 'truce' and args.kind ~= 'alliance') then return end
    local key = args.id .. '#' .. tostring(args.revision)
    if View.agreementsShown[key] then return end
    View.agreementsShown[key] = true
    local name = type(args.groupName) == 'string' and args.groupName or ''
    if not p then return end
    if name ~= '' then HaloTextHelper.addGoodText(p, getText('IGUI_LK_Agreement_' .. args.kind, name))
    else HaloTextHelper.addGoodText(p, getText('IGUI_LK_AgreementUnnamed_' .. args.kind)) end
end

local function incident(args, p)
    if type(args.id) ~= 'string'
            or (args.decision ~= 'maintain' and args.decision ~= 'repair' and args.decision ~= 'break') then return end
    if View.incidentsShown[args.id] then return end
    View.incidentsShown[args.id] = true
    local name = type(args.groupName) == 'string' and args.groupName or ''
    if name == '' then name = getText('IGUI_LK_IncidentGroup') end
    if not p then return end
    local text
    if args.decision == 'repair' and type(args.category) == 'string' and args.category:match('^%a+$') then
        text = getText('IGUI_LK_Incident_repair', name, getText('IGUI_LK_RepairCategory_' .. args.category))
    elseif args.decision ~= 'repair' then
        text = getText('IGUI_LK_Incident_' .. args.decision, name)
    else return end
    if args.decision == 'break' then HaloTextHelper.addBadText(p, text)
    else HaloTextHelper.addGoodText(p, text) end
end

View.commands = {agreement = agreement, incident = incident}

-- p: player who sees the notice (the local player when nil).
function View.receive(command, args, p)
    local fn = View.commands[command]
    if not fn or type(args) ~= 'table' then return end
    fn(args, p or getSpecificPlayer(0))
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE then return end
    View.receive(command, args)
end

if isClient() then   -- solo: View.receive called by the authority, no server command
    LivingKnox.subscribe("OnServerCommand", "AgreementNoticesView.onServerCommand", function(module, command, args)
        LivingKnox.AgreementNoticesView.onServerCommand(module, command, args)
    end)
end

return View
