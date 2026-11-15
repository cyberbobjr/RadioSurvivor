-- Notebook view of the template `deliver` (M01): items handed over to the requester (a radio voice: at its dead drops),
-- or a supply offer of a Living Knox group counted in value points (E17-T03). Also the view of a row without a
-- template name (a saved mission without the field is a `deliver`) or with an unknown one.
local Views = require 'RadioSurvivor/RS_MissionViews'

local function supply(row, line, ctx)
    local tr = ctx.tr
    line(tr('SupplyProgress', row.delivered, row.quantity))
    local accepted = {}
    for fullType in pairs(row.accepted) do
        accepted[#accepted + 1] = ctx.itemName(fullType) .. ' (' .. tostring((row.values or {})[fullType] or 0) .. ')'
    end
    table.sort(accepted)
    line(tr('AcceptedItems', table.concat(accepted, ', ')))
    line(tr('SupplyValues'))
end

-- E20-T05: every drop point of a voice mission (labels of its sheet), at the player's choice; deposits add up.
local function deadDrops(row, line, tr)
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

local function items(row, line, ctx)
    local tr = ctx.tr
    line(tr('Progress', row.delivered, row.quantity))
    if ctx.voice then deadDrops(row, line, tr) end
    local accepted = {}
    for fullType in pairs(row.accepted) do accepted[#accepted + 1] = ctx.itemName(fullType) end
    table.sort(accepted)
    line(tr('AcceptedItems', table.concat(accepted, ', ')))
    line(tr('OneUnit'))
end

local Deliver = Views.register('deliver', {
    showsPlace = false,
    detail = function(row, line, ctx)
        if row.unit == 'value' then supply(row, line, ctx) else items(row, line, ctx) end
    end})

Views.setDefault(Deliver)
