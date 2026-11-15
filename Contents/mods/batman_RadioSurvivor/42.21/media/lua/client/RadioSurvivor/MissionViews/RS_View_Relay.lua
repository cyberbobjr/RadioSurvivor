-- Notebook view of the template `relay` (E20-T12): a powered two-way radio turned on high at a place named by a radio
-- voice, read by the server, then the report on the voice's frequency.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('relay', {
    showsPlace = false,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        line(tr('RelayPlace', row.place or ''))
        if row.mapZone then line(tr('RelayMapZone')) end
        line(tr('RelayLevel', row.minZ or 1))
        line(tr(row.relayed and 'RelayOn' or 'RelayOff'))
        line(tr('RelayRule')); line(tr('RelayReport'))
    end})
