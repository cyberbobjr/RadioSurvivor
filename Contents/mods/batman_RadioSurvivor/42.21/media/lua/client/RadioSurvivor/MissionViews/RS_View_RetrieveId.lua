-- Notebook view of the template `retrieve_id` (E11-T05): bring back the ID card of a body. E20-T06: for a radio voice,
-- the card is left at one of the mission's dead drops (no hand-over in person).
local Views = require 'RadioSurvivor/RS_MissionViews'
local DeadDrops = require 'RadioSurvivor/RS_DeadDropLines'

Views.register('retrieve_id', {
    showsPlace = true,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        if row.mapZone and not row.found then line(tr('RetrieveMapZone')) end
        if row.person and row.person ~= '' then line(tr('RetrievePerson', row.person)) end
        line(row.found and tr('RetrieveFound', row.foundBy) or tr('RetrieveNotFound'))
        if ctx.voice then
            line(tr('RetrieveDropCard'))
            DeadDrops.write(row, line, tr)
        else
            line(tr('RetrieveReport'))
        end
    end})
