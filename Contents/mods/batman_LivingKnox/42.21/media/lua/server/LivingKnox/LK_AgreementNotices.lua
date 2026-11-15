if isClient() then return end
--[[
Living Knox: on-screen notices of its agreements and incidents (E09-T05, E09-T06; moved from the notebook server by
E21-T04). Authority only; the view is client/LivingKnox/LK_AgreementNoticesView.lua (LivingKnox.AgreementNoticesView).

  agreement   an agreement became applicable (LK_Agreements.onApplied): announced to the connected players of its
              team with the readable name of the group, once per agreement revision (the view keeps what it showed).
  incident    decision of a group leader on an incident (LK_Talk, incidentReply): maintain, repair or break,
              announced to the connected players of the team.

Network module LivingKnox, commands "agreement" { id, revision, kind, state, groupName } and "incident" { id,
decision, category, revision, groupName }. Solo: the view is called directly (same Lua, no server command). After an
agreement the host of the speech (the notebook) publishes its views again (relation panels show its state).
]]
require 'LivingKnox/LK_Core'
local Agreements = require 'LivingKnox/LK_Agreements'

local Notices = LivingKnox.AgreementNotices or {}
LivingKnox.AgreementNotices = Notices
Notices.MODULE = 'LivingKnox'

local function online()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    elseif getPlayer() then out[1] = getPlayer() end
    return out
end

-- Sends one notice to the connected players of a team.
local function tell(team, command, args)
    for _, p in ipairs(Agreements.membersOnline(team, online())) do
        if isServer() then sendServerCommand(p, Notices.MODULE, command, args)
        else
            local View = LivingKnox.AgreementNoticesView
            if View and View.receive then View.receive(command, args, p) end
        end
    end
end

-- Readable name of a group ('' when unknown).
local function groupName(gid)
    local G = LivingKnox.Groups
    local g = G and G.peek and type(gid) == 'string' and G.peek(gid) or nil
    return g and tostring(g.name or '') or ''
end

function Notices.agreement(a)
    tell(a.team, 'agreement', {id = a.id, revision = a.revision, kind = a.kind, state = a.state,
        groupName = groupName(a.group)})
    local host = LivingKnox.Talk and LivingKnox.Talk.host
    if host and host.publish then host.publish() end
end

function Notices.incident(a, inc, npc)
    tell(a.team, 'incident', {id = inc.id, decision = inc.decision, category = inc.category or '',
        revision = a.revision, groupName = npc and npc.groupName or ''})
end

-- One listener, even after a Lua reload of this file (it reads the current Notices.agreement).
if not Notices.subscribed then
    Notices.subscribed = true
    Agreements.onApplied(function(a) Notices.agreement(a) end)
end

return Notices
