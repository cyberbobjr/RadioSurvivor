-- Notebook view of the template `deliver` (M01): items handed over to the requester (a radio voice: at its dead drops),
-- or a supply offer of a Living Knox group counted in value points (E17-T03). Also the view of a row without a
-- template name (a saved mission without the field is a `deliver`) or with an unknown one.
local Views = require 'RadioSurvivor/RS_MissionViews'
local DeadDrops = require 'RadioSurvivor/RS_DeadDropLines' -- E20-T05: drop points of a voice mission

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

local function items(row, line, ctx)
    local tr = ctx.tr
    line(tr('Progress', row.delivered, row.quantity))
    if ctx.voice then DeadDrops.write(row, line, tr) end
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
