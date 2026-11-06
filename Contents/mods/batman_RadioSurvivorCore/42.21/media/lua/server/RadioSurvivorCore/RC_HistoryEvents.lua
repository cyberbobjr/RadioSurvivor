if isClient() then return end
-- RadioSurvivorCore: engine events of the exchange history of the core mod (E18-T26). The core mod reads its own
-- history at the world start, whatever mod writes in it (RadioSurvivor's notebook state also calls RC_History.init,
-- which reads the same file again), and writes it back every ten game minutes when a line was added.
local History = require 'RadioSurvivorCore/RC_History'
local WorldStart = require 'RadioSurvivorCore/RC_WorldStart'

if not History.subscribed then
    History.subscribed = true
    Events.OnInitGlobalModData.Add(function(newWorld)
        if History.data == nil and not History.blocked then History.init(WorldStart.isNewWorld(newWorld == true)) end
    end)
    Events.EveryTenMinutes.Add(function()
        if History.dirty then History.save() end
    end)
end
