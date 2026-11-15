--[[
CoreAI: constants of the notebook protocol (E21-T03, design carnet-commun-e21.md, "Configuration et stocks").
Read by the notebook client (CA_NotebookClient) and by the notebook server (the configuration of the mod that hosts
it gives the same values under the same names). The notebook traffic uses the network module MODULE, shared with
the other commands of the core mod (CA_Identity, CA_MissionJournal, CA_Teams): each command name has one owner (see
the server registry).
]]
local MissionConfig = require 'CoreAI/CA_MissionConfig'

local Config = {
    MODULE = 'CoreAI',
    VERSION = 2,
    DELIVERY_RANGE = MissionConfig.DELIVERY_RANGE,
    -- E17-T15: longer than the longest answer of the bridge (bridge/radio_bridge.py: start at most MAX_AGE_S = 75 s
    -- after `sent`, then one model call of at most LLM_BUDGET_S = 60 s, attempts included: 135 s). An error of the
    -- provider comes back sooner as a reply with `error` (timeout, http_503...), refused with that cause.
    SAVE_INTERVAL_MS = 5000, -- only while a mission clock runs or the state changed
    -- Snapshot polling by the client: open notebook vs. closed (identity/session keep-alive).
    SNAPSHOT_OPEN_MS = 3000,
    SNAPSHOT_CLOSED_MS = 30000,
    -- Lifecycle of missions and NPC fiches; keeps the private state bounded on long servers.
    NPC_UNSEEN_MS = 3600000, -- uncontacted fiche dropped after 1 h without a loaded body
    PRUNE_INTERVAL_MS = 60000,
}

return Config
