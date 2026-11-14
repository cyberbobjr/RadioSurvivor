-- Notebook view of the template `retrieve_id` (E11-T05): bring back the ID card of a body.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('retrieve_id', {
    showsPlace = true,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        if row.mapZone and not row.found then line(tr('RetrieveMapZone')) end
        if row.person and row.person ~= '' then line(tr('RetrievePerson', row.person)) end
        line(row.found and tr('RetrieveFound', row.foundBy) or tr('RetrieveNotFound'))
        line(tr('RetrieveReport'))
    end})
