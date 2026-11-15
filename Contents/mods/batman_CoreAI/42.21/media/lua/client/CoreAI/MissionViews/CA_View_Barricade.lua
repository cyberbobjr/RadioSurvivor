-- Notebook view of the template `barricade` (E20-T09): outside windows and doors of a building named by the giver,
-- counted by the server, then the report to the giver.
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

Views.register('barricade', {
    showsPlace = false,
    detail = function(row, line)
        line(tr('BarricadePlace', row.place or ''))
        if row.mapZone then line(tr('BarricadeMapZone')) end
        line(tr('BarricadeProgress', row.barricaded or 0, row.count or 0))
        line(tr('BarricadeRule')); line(tr('BarricadeReport'))
    end})
