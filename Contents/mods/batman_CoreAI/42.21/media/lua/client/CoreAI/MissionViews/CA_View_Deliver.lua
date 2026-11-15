-- Notebook view of the template `deliver` (M01): items handed over to the requester (a remote giver adds its own lines
-- at the section point, e.g. its drop points), or a supply offer of an NPC group counted in value points (E17-T03).
-- Also the view of a row without a template name (a saved mission without the field is a `deliver`) or with an
-- unknown one.
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

local function supply(row, line, ctx)
    line(tr('SupplyProgress', row.delivered, row.quantity))
    local accepted = {}
    for fullType in pairs(row.accepted) do
        accepted[#accepted + 1] = ctx.itemName(fullType) .. ' (' .. tostring((row.values or {})[fullType] or 0) .. ')'
    end
    table.sort(accepted)
    line(tr('AcceptedItems', table.concat(accepted, ', ')))
    line(tr('SupplyValues'))
end

local function items(row, line, ctx)
    line(tr('Progress', row.delivered, row.quantity))
    Views.section('deliver', row, line, ctx)
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
