-- Notebook view of the template `recover` (E11-T06): carry the cache bag to the depot of the group.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('recover', {
    showsPlace = true,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        if row.mapZone and not row.found then line(tr('RecoverMapZone')) end
        if row.cache and row.cache ~= '' then line(tr('RecoverCache', getText('IGUI_RS_Cache_' .. row.cache))) end
        line(row.found and tr('RecoverFound', row.foundBy) or tr('RecoverNotFound'))
        if row.depotZone then line(tr('RecoverDepotZone')) end
        line(tr('RecoverReport'))
    end})
