-- Notebook lines of the dead drops of a radio voice mission (E20-T05, E20-T06): every drop point of the mission (labels
-- of its sheet), at the player's choice, deposits adding up; how to leave the items and when they are collected.
-- Shared by the views of the templates that declare dead drops (RS_View_Deliver, RS_View_RetrieveId, RS_View_Item).
-- Row fields (RS_DeadDrops.project on the server): drops = { {label, mode, ready} }, collectHours, depositCollected.
local Lines = {}

function Lines.write(row, line, tr)
    local labels, approach, modes = {}, false, {}
    for _, d in ipairs(type(row.drops) == 'table' and row.drops or {}) do
        labels[#labels + 1] = tostring(d.label)
        if not d.ready then approach = true end
        modes[d.mode == 'bag' and 'bag' or 'box'] = true
    end
    line(tr('DeadDropPoints', table.concat(labels, ', ')))
    if approach then line(tr('DeadDropApproach')) end
    if modes.box then line(tr('DeadDropBox')) end
    if modes.bag then line(tr('DeadDropBag')) end
    line(row.depositCollected and tr('DeadDropCollected') or tr('DeadDropLeave', tostring(row.collectHours or '')))
end

return Lines
