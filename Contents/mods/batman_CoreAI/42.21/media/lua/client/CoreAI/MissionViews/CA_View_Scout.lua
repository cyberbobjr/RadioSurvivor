-- Notebook view of the template `scout` (E11-T03): reach a place, then report in person (a remote giver writes its own
-- lines at the section point).
local Views = require 'CoreAI/CA_MissionViews'
local tr = Views.tr

local function inPerson(row, line)
    line(row.zoneReached and tr('ScoutReached', row.reachedBy) or tr('ScoutNotReached')); line(tr('ScoutReport'))
end

Views.register('scout', {
    showsPlace = true,
    detail = function(row, line, ctx)
        -- E11-T10: approximate area drawn on the world map (missions created since).
        if row.mapZone and not row.zoneReached then line(tr('ScoutMapZone')) end
        Views.section('scout', row, line, ctx, inPerson)
    end})
