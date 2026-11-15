-- Notebook view of the template `item` (E20-T15): find a personal item the server put at a place named by the giver,
-- leave it where the giver says (its section: drop points), then report to the giver.
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

Views.register('item', {
    showsPlace = false,
    detail = function(row, line, ctx)
        local label = type(row.itemLabel) == 'string' and row.itemLabel or ''
        line(tr('ItemWhat', label ~= '' and label or ctx.itemName(row.itemType or '')))
        line(tr('ItemPlace', row.place or ''))
        if row.mapZone and not row.found then line(tr('ItemMapZone')) end
        line(row.found and tr('ItemFound', row.foundBy or '') or tr('ItemNotFound'))
        line(tr('ItemDropIt'))
        Views.section('item', row, line, ctx)
        line(tr('ItemOnlyThis'))
        line(tr('ItemReport'))
    end})
