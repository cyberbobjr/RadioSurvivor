--[[
RST_ViewSteps - client checks asked by the authority through RST.Steps for the suites that were "solo only" because
what they check is drawn or kept by the displaying client (E01-T19). Development mod only. Load with:
require "RST/RST_ViewSteps" (shared: the handlers are registered on every side; they run on the clients and, in
solo, in the same Lua state). The suites keep their solo code path; on a dedicated server (RST.server, campaign mp)
they act on the authority and ask these steps to the requester client (target "requester").
E21-T07: this file holds the table RST.ViewSteps and the steps of the core mod; each test mod adds its own steps to
the same table (RST_LKViewSteps.lua in batman_LivingKnoxTests, RST_RSViewSteps.lua in batman_RadioSurvivorTests).

Client handlers (RST.Steps.on):
    core.journal.act  { action, mission, revision }: the gesture of a button of the Missions tab of the core notebook
                      (E21-T04: notebook command of the action, CoreAI.notebookClient.send), sent to the authority.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.ViewSteps = RST.ViewSteps or {}
local VS = RST.ViewSteps
local Steps = RST.Steps

VS.counters = VS.counters or {}   -- key -> state of the counting steps (clients, solo)

-- ---------------------------------------------------------------- core.journal.act (E18-T29)

-- The gesture of a button of the Missions tab of the core notebook (E21-T04: notebook command of the action).
Steps.on("core.journal.act", function(args)
    local Client = CoreAI and CoreAI.notebookClient
    if Client == nil or Client.send == nil then return Steps.fail("notebook client of the core mod not loaded here") end
    Client.send(tostring(args.action), { mission = args.mission, revision = args.revision })
    return Steps.pass("sent " .. tostring(args.action))
end)

return VS
