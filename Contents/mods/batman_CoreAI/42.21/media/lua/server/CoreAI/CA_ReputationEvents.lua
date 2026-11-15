if isClient() then return end
-- CoreAI: engine events of the reputation of the core mod (E18-T22): state read at the world start, purge
-- clock started at the death of a character, purge every game day (CA_Reputation).
local Reputation = require 'CoreAI/CA_Reputation'
local Identity = require 'CoreAI/CA_Identity'

if not Reputation.subscribed then
    Reputation.subscribed = true
    Identity.onRetire(Reputation.onRetire)
    Events.OnInitGlobalModData.Add(Reputation.init)
    Events.EveryDays.Add(Reputation.everyDay)
end
