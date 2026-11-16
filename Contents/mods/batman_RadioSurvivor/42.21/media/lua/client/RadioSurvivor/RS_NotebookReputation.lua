--[[
RadioSurvivor's part of the Reputation tab of the common notebook (E04-T04, E21-T03: moved from RS_Notebook). The tab
belongs to the core mod (CA_NotebookReputation); RadioSurvivor gives the texts of its own acts and, apart, the personal
trust of each known NPC (it is not the reputation), in the words of the NPC engine's page (Notebook.relationLevel;
nothing without it).
]]
local Notebook = require 'CoreAI/CA_Notebook'

local function tr(key, ...) return getText('IGUI_RS_' .. key, ...) end

Notebook.reputationReasons['trade.cheated'] = 'IGUI_RS_RepReason_TradeCheated'
Notebook.reputationReasons['trade.nodrop'] = 'IGUI_RS_RepReason_TradeNoDrop'
Notebook.reputationReasons['npc.requesterKilled'] = 'IGUI_RS_RepReason_RequesterKilled'
Notebook.reputationReasons['rescue.success'] = 'IGUI_RS_RepReason_RescueSuccess'

-- Personal trust of each living known NPC (snapshot contacts), after the reputation of the character.
local function trustLines(snapshot)
    local out = {tr('PersonalTrustSeparate')}
    local any = false
    for _, c in ipairs(type(snapshot.contacts) == 'table' and snapshot.contacts or {}) do
        local rel = type(c.relation) == 'table' and c.relation or nil
        local word = rel and Notebook.relationLevel and Notebook.relationLevel(rel.level)
        if word and c.alive ~= false then
            out[#out + 1] = '- ' .. tr('RepTrust', c.name, word)
            any = true
        end
    end
    if not any then out[#out + 1] = tr('RepNoTrust') end
    return out
end
Notebook.reputationExtras[#Notebook.reputationExtras + 1] = trustLines

return {trustLines = trustLines}
