-- Presentation of the missions given by a radio voice in the notebook (E21-T03): giver kind 'voice' of the core
-- registry (CA_MissionViews.registerGiver). A voice has no body to join: the report goes on its frequency, items and
-- cards are left at its dead drops (RS_DeadDropLines), a reached place is reported by radio.
local Views = require 'CoreAI/CA_MissionViews'
local DeadDrops = require 'RadioSurvivor/RS_DeadDropLines'

local function tr(key, ...) return getText('IGUI_RS_' .. key, ...) end

local function deadDrops(row, line) DeadDrops.write(row, line, tr) end

Views.registerGiver('voice', {
    remote = true,
    reportLine = function(row) return tr('ReportRadio', row.requester) end,
    sections = {
        deliver = deadDrops, -- E20-T05: drop points of a voice mission
        item = deadDrops,
        retrieve_id = function(row, line) -- E20-T06: the card is left at a drop point (no hand-over in person)
            line(tr('RetrieveDropCard'))
            deadDrops(row, line)
        end,
        scout = function(row, line)
            line(row.zoneReached and tr('ScoutReachedRadio', row.reachedBy) or Views.tr('ScoutNotReached'))
            line(tr('ScoutReportRadio'))
        end,
    }})

return Views.giver('voice')
