-- Notebook view of the template `item` (E20-T15): find a personal item the server put at a place named by a radio
-- voice, leave it at one of the mission's dead drops, then report on the voice's frequency.
local Views = require 'RadioSurvivor/RS_MissionViews'
local DeadDrops = require 'RadioSurvivor/RS_DeadDropLines'

Views.register('item', {
    showsPlace = false,
    detail = function(row, line, ctx)
        local tr = ctx.tr
        local label = type(row.itemLabel) == 'string' and row.itemLabel or ''
        line(tr('ItemWhat', label ~= '' and label or ctx.itemName(row.itemType or '')))
        line(tr('ItemPlace', row.place or ''))
        if row.mapZone and not row.found then line(tr('ItemMapZone')) end
        line(row.found and tr('ItemFound', row.foundBy or '') or tr('ItemNotFound'))
        line(tr('ItemDropIt'))
        DeadDrops.write(row, line, tr)
        line(tr('ItemOnlyThis'))
        line(tr('ItemReport'))
    end})
