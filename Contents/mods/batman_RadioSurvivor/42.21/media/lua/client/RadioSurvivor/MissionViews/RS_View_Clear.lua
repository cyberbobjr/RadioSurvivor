-- Notebook view of the template `clear` (E11-T04): kill zombies inside the circle drawn on the map.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('clear', {
    showsPlace = true,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        if row.mapZone then line(tr('ClearMapZone')) end
        line(tr('ClearProgress', row.kills, row.target))
        for _, part in ipairs(type(row.tally) == 'table' and row.tally or {}) do
            line('- ' .. tr('ClearBy', part.name, part.count))
        end
        line(tr('ClearRule')); line(tr('ClearReport'))
    end})
