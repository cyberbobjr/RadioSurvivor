if isClient() then return end
-- RadioSurvivorCore: engine events of the team ids (E18-T20, RC_Teams): state read at the world start, commands of the
-- Team tab of the notebook.
local Teams = require 'RadioSurvivorCore/RC_Teams'

if not Teams.subscribed then
    Teams.subscribed = true
    Events.OnInitGlobalModData.Add(function(newWorld) Teams.init(newWorld) end)
    Events.OnClientCommand.Add(Teams.onClientCommand)
end
