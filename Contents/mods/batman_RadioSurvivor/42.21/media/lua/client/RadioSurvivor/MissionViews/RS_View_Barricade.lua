-- Notebook view of the template `barricade` (E20-T09): outside windows and doors of a building named by a radio voice,
-- counted by the server, then the report on the voice's frequency.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('barricade', {
    showsPlace = false,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        line(tr('BarricadePlace', row.place or ''))
        if row.mapZone then line(tr('BarricadeMapZone')) end
        line(tr('BarricadeProgress', row.barricaded or 0, row.count or 0))
        line(tr('BarricadeRule')); line(tr('BarricadeReport'))
    end})
