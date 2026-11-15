--[[
RST_ModLivingKnox - registers Living Knox in the mods guard of RST (E21-T07): short name "lk", mod id
batman_LivingKnox, suites "lk.*". Development mod only (batman_LivingKnoxTests).
]]

require "RST/RST"

RST.registerMod("lk", "batman_LivingKnox", "lk.")

-- Tool of the admin window reachable by the step rst.request (RST_PeerChecks.lua).
RST.PeerChecks = RST.PeerChecks or {}
RST.PeerChecks.MODULES = RST.PeerChecks.MODULES or {}
RST.PeerChecks.MODULES.LivingKnox = { adminRequest = "adminReply" }

-- Bookmark of Living Knox in the core notebook, after the core tabs (suite ca.notebook, E18-T20).
RST.NotebookTabs = RST.NotebookTabs or {}
RST.NotebookTabs.Team = 50
