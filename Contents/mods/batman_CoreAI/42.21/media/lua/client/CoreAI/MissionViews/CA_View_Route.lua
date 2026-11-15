-- Notebook view of the template `route` (E20-T13): places named by the giver crossed in order, read by the server,
-- then the report to the giver. Only the next place is named (the later ones stay unknown).
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

Views.register('route', {
    showsPlace = false,
    detail = function(row, line)
        line(tr('RouteProgress', row.routeDone or 0, row.routeTotal or 0))
        if row.routeNext then line(tr('RouteNext', row.routeNext)) else line(tr('RouteAllCrossed')) end
        if row.mapZones then line(tr('RouteMapZone')) end
        line(tr('RouteRule')); line(tr('RouteReport'))
    end})
