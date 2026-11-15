-- Notebook view of the template `relay` (E20-T12): a powered two-way radio turned on high at a place named by the
-- giver, read by the server, then the report to the giver.
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

Views.register('relay', {
    showsPlace = false,
    detail = function(row, line)
        line(tr('RelayPlace', row.place or ''))
        if row.mapZone then line(tr('RelayMapZone')) end
        line(tr('RelayLevel', row.minZ or 1))
        line(tr(row.relayed and 'RelayOn' or 'RelayOff'))
        line(tr('RelayRule')); line(tr('RelayReport'))
    end})
