-- Notebook view of the template `retrieve_id` (E11-T05): bring back the ID card of a body. E20-T06: a remote giver
-- says where to leave the card (its section) instead of the report in person.
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

local function inPerson(_, line) line(tr('RetrieveReport')) end

Views.register('retrieve_id', {
    showsPlace = true,
    detail = function(row, line, ctx)
        if row.mapZone and not row.found then line(tr('RetrieveMapZone')) end
        if row.person and row.person ~= '' then line(tr('RetrievePerson', row.person)) end
        line(row.found and tr('RetrieveFound', row.foundBy) or tr('RetrieveNotFound'))
        Views.section('retrieve_id', row, line, ctx, inPerson)
    end})
