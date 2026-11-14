-- Notebook view of the template `signal` (E11-T07): light a signal of a colour in the circle, at an hour.
local Views = require 'RadioSurvivor/RS_MissionViews'

Views.register('signal', {
    showsPlace = true,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        if row.mapZone then line(tr('SignalMapZone')) end
        line(tr('SignalColor', getText('IGUI_RS_SignalColor_' .. tostring(row.color))))
        line(tr('SignalHour', row.hour, (row.hour + row.windowHours) % 24))
        line(row.lit and tr('SignalLit', row.litBy) or tr('SignalNotLit'))
        line(tr('SignalRule')); line(tr('SignalReport'))
    end})
