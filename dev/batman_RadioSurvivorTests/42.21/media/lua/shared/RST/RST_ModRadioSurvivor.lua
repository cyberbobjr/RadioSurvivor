--[[
RST_ModRadioSurvivor - registers RadioSurvivor in the mods guard of RST (E21-T07): short name "rs", mod id
batman_RadioSurvivor, suites "rs.*"; the group radio refreshed when a test fixture creates or removes a group
(RST.GroupRefresh, read by the group fixture of another test mod when it is loaded). Development mod only
(batman_RadioSurvivorTests).
]]

require "RST/RST"

RST.registerMod("rs", "batman_RadioSurvivor", "rs.")

RST.GroupRefresh = RST.GroupRefresh or {}
RST.GroupRefresh.radioSurvivor = function()
    local ok, R = pcall(require, "RadioSurvivor/RS_GroupRadio")
    if ok and type(R) == "table" and type(R.refresh) == "function" then R.refresh() end
end

-- Tool of the frequency debug window reachable by the step rst.request (RST_PeerChecks.lua).
RST.PeerChecks = RST.PeerChecks or {}
RST.PeerChecks.MODULES = RST.PeerChecks.MODULES or {}
RST.PeerChecks.MODULES.RadioSurvivorDebug = { freqRequest = "freqReply" }
-- E22-T08: place survey of the voice workshop (rs.placesurvey: a user client is refused).
RST.PeerChecks.MODULES.RadioSurvivorSurvey = { surveyPlace = "surveyReply" }

-- Bookmark of RadioSurvivor in the core notebook, before the core tabs (suite ca.notebook).
RST.NotebookTabs = RST.NotebookTabs or {}
RST.NotebookTabs.Radio = 10
