-- Notebook view of the template `scout` (E11-T03): reach a place, then report in person or on the voice's frequency.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('scout', {
    showsPlace = true,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        -- E11-T10: approximate area drawn on the world map (missions created since).
        if row.mapZone and not row.zoneReached then line(tr('ScoutMapZone')) end
        if ctx.voice then
            line(row.zoneReached and tr('ScoutReachedRadio', row.reachedBy) or tr('ScoutNotReached'))
            line(tr('ScoutReportRadio'))
        else
            line(row.zoneReached and tr('ScoutReached', row.reachedBy) or tr('ScoutNotReached')); line(tr('ScoutReport'))
        end
    end})
