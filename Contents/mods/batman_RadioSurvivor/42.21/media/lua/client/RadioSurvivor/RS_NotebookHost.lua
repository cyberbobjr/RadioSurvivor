--[[
RadioSurvivor: notices of the notebook server it still hosts (E21-T03, moved unchanged from RS_Client). The notebook
server announces the agreements and incidents of Living Knox to the player; RadioSurvivor shows them through the
client command registry of the core notebook (CoreAI.notebookClient.registerCommand) until they move to Living Knox
(design carnet-commun-e21.md, LK_AgreementNotices).
]]
local Client = require 'CoreAI/CA_NotebookClient'

-- E09-T05: agreement of this player's team with a group, announced by the server once applied (its members stopped
-- aiming at the team), once per agreement revision.
Client.registerCommand('agreement', function(args, p)
    if args.world ~= Client.world or args.run ~= Client.run or type(args.id) ~= 'string'
            or (args.kind ~= 'truce' and args.kind ~= 'alliance') then return end
    local key = args.id .. '#' .. tostring(args.revision)
    Client.agreementsShown = Client.agreementsShown or {}
    if Client.agreementsShown[key] then return end
    Client.agreementsShown[key] = true
    local name = type(args.groupName) == 'string' and args.groupName or ''
    if p then
        if name ~= '' then HaloTextHelper.addGoodText(p, getText('IGUI_RS_Agreement_' .. args.kind, name))
        else HaloTextHelper.addGoodText(p, getText('IGUI_RS_AgreementUnnamed_' .. args.kind)) end
    end
end)

-- E09-T06: decision of a group leader on an incident of this player's team (maintain, repair, break), once.
Client.registerCommand('incident', function(args, p)
    if args.world ~= Client.world or args.run ~= Client.run or type(args.id) ~= 'string'
            or (args.decision ~= 'maintain' and args.decision ~= 'repair' and args.decision ~= 'break') then return end
    Client.incidentsShown = Client.incidentsShown or {}
    if Client.incidentsShown[args.id] then return end
    Client.incidentsShown[args.id] = true
    local name = type(args.groupName) == 'string' and args.groupName or ''
    if name == '' then name = getText('IGUI_RS_IncidentGroup') end
    if p then
        local text
        if args.decision == 'repair' and type(args.category) == 'string' and args.category:match('^%a+$') then
            text = getText('IGUI_RS_Incident_repair', name, getText('IGUI_RS_RepairCategory_' .. args.category))
        elseif args.decision ~= 'repair' then
            text = getText('IGUI_RS_Incident_' .. args.decision, name)
        else return end
        if args.decision == 'break' then HaloTextHelper.addBadText(p, text)
        else HaloTextHelper.addGoodText(p, text) end
    end
end)

return Client
