-- Notebook view of the template `watch` (E20-T14): keep watch at a place named by the giver for some game hours, time
-- read by the server, then the report to the giver.
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

Views.register('watch', {
    showsPlace = false,
    detail = function(row, line)
        line(tr('WatchPlace', row.place or ''))
        if row.mapZone then line(tr('WatchMapZone')) end
        line(tr('WatchProgress', row.watchedMinutes or 0, row.hours or 0))
        if row.watchDone then line(tr('WatchDone')) end
        line(tr('WatchRule', row.radius or 0, row.absenceMinutes or 0))
        line(tr('WatchReport'))
    end})
